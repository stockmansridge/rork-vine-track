import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Promise<Response>): void;
};

interface RecoveryRequest {
  email?: string;
  redirect_to?: string;
}

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function randomPassword(): string {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function renderEmail(actionLink: string): { subject: string; html: string; text: string } {
  const escapedLink = escapeHtml(actionLink);
  const subject = "Reset your VineTrack password";
  const html = `<!doctype html>
<html>
  <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;background:#f6f6f4;margin:0;padding:24px;color:#1c1c1e;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:520px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.05);">
      <tr>
        <td style="padding:32px 32px 16px 32px;">
          <div style="font-size:14px;color:#6e6e73;letter-spacing:0.04em;text-transform:uppercase;font-weight:600;">VineTrack</div>
          <h1 style="margin:12px 0 8px 0;font-size:26px;line-height:1.2;font-weight:700;color:#1c1c1e;">Reset your password</h1>
          <p style="margin:0;font-size:16px;line-height:1.5;color:#3a3a3c;">Use the secure link below to set a new VineTrack password.</p>
        </td>
      </tr>
      <tr>
        <td style="padding:8px 32px 24px 32px;">
          <a href="${escapedLink}" style="display:inline-block;background:#5d3a7e;color:#ffffff;text-decoration:none;padding:14px 24px;border-radius:12px;font-weight:600;font-size:16px;">Reset Password</a>
          <p style="margin:20px 0 0 0;font-size:14px;line-height:1.5;color:#6e6e73;">This link expires soon. If the button does not work, copy and paste this URL into Safari:</p>
          <p style="word-break:break-all;font-size:12px;line-height:1.5;color:#6e6e73;">${escapedLink}</p>
        </td>
      </tr>
      <tr>
        <td style="padding:16px 32px 32px 32px;border-top:1px solid #e5e5ea;">
          <p style="margin:0;font-size:12px;color:#8e8e93;line-height:1.5;">If you did not request this, you can safely ignore this email.</p>
        </td>
      </tr>
    </table>
  </body>
</html>`;
  const text = `Reset your VineTrack password\n\nOpen this secure link to set a new password:\n${actionLink}\n\nIf you did not request this, you can safely ignore this email.`;
  return { subject, html, text };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let payload: RecoveryRequest;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const email = (payload.email ?? "").trim().toLowerCase();
  if (!email || !email.includes("@")) {
    return json({ error: "Invalid email" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("PASSWORD_RESET_FROM_EMAIL") ?? Deno.env.get("INVITE_FROM_EMAIL");

  if (!supabaseUrl || !serviceRoleKey || !resendApiKey || !fromEmail) {
    const missing = [
      !supabaseUrl ? "SUPABASE_URL" : null,
      !serviceRoleKey ? "SUPABASE_SERVICE_ROLE_KEY" : null,
      !resendApiKey ? "RESEND_API_KEY" : null,
      !fromEmail ? "PASSWORD_RESET_FROM_EMAIL or INVITE_FROM_EMAIL" : null,
    ].filter((value): value is string => value !== null);
    console.error("[send-password-recovery-email] missing configuration", missing);
    return json({ error: "Password recovery email service is not configured", missing }, 503);
  }

  const redirectTo = payload.redirect_to ?? "vinetrack://reset-password?flow=recovery";
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  let actionLink: string | undefined;
  let mode = "recovery";

  const recovery = await admin.auth.admin.generateLink({
    type: "recovery",
    email,
    options: { redirectTo },
  });

  actionLink = recovery.data?.properties?.action_link;

  if (!actionLink) {
    const signup = await admin.auth.admin.generateLink({
      type: "signup",
      email,
      password: randomPassword(),
      options: {
        redirectTo,
        data: { full_name: email },
      },
    });
    actionLink = signup.data?.properties?.action_link;
    mode = "signup";

    if (!actionLink) {
      console.error("[send-password-recovery-email] link generation failed", {
        recovery: recovery.error?.message,
        signup: signup.error?.message,
      });
      return json({ ok: true }, 200);
    }
  }

  const emailContent = renderEmail(actionLink);
  const resendResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: fromEmail,
      to: [email],
      subject: emailContent.subject,
      html: emailContent.html,
      text: emailContent.text,
    }),
  });

  if (!resendResponse.ok) {
    const body = await resendResponse.text();
    console.error("[send-password-recovery-email] Resend error", resendResponse.status, body);
    return json({ error: "Email provider rejected the request" }, 502);
  }

  return json({ ok: true, mode });
});
