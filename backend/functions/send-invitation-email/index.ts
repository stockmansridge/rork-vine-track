declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Promise<Response>): void;
};

interface InvitePayload {
  email?: string;
  vineyard_name?: string;
  role?: string;
  invited_by_name?: string;
  invitation_id?: string;
  app_store_url?: string;
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

function renderEmail(payload: {
  vineyardName: string;
  role: string;
  invitedByName: string;
  acceptUrl: string;
}): { subject: string; html: string; text: string } {
  const subject = `You've been invited to ${payload.vineyardName} on VineTrack`;
  const html = `<!doctype html>
<html>
  <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;background:#f6f6f4;margin:0;padding:24px;color:#1c1c1e;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:520px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.05);">
      <tr>
        <td style="padding:32px 32px 16px 32px;">
          <div style="font-size:14px;color:#6e6e73;letter-spacing:0.04em;text-transform:uppercase;font-weight:600;">VineTrack</div>
          <h1 style="margin:12px 0 8px 0;font-size:26px;line-height:1.2;font-weight:700;color:#1c1c1e;">You've been invited to ${escapeHtml(payload.vineyardName)}</h1>
          <p style="margin:0;font-size:16px;line-height:1.5;color:#3a3a3c;">${escapeHtml(payload.invitedByName)} invited you to join <strong>${escapeHtml(payload.vineyardName)}</strong> as <strong>${escapeHtml(payload.role)}</strong>.</p>
        </td>
      </tr>
      <tr>
        <td style="padding:8px 32px 24px 32px;">
          <a href="${escapeHtml(payload.acceptUrl)}" style="display:inline-block;background:#5d3a7e;color:#ffffff;text-decoration:none;padding:14px 24px;border-radius:12px;font-weight:600;font-size:16px;">Open VineTrack</a>
          <p style="margin:20px 0 0 0;font-size:14px;line-height:1.5;color:#6e6e73;">Open VineTrack and sign in with this email address to accept. If you don't have the app yet, tap the button above to install it.</p>
        </td>
      </tr>
      <tr>
        <td style="padding:16px 32px 32px 32px;border-top:1px solid #e5e5ea;">
          <p style="margin:0;font-size:12px;color:#8e8e93;line-height:1.5;">If you weren't expecting this invitation, you can safely ignore this email.</p>
        </td>
      </tr>
    </table>
  </body>
</html>`;
  const text = `You've been invited to ${payload.vineyardName} on VineTrack\n\n${payload.invitedByName} invited you to join ${payload.vineyardName} as ${payload.role}.\n\nOpen VineTrack: ${payload.acceptUrl}\n\nSign in with this email address to accept.`;
  return { subject, html, text };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let payload: InvitePayload;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const email = (payload.email ?? "").trim().toLowerCase();
  if (!email || !email.includes("@")) {
    return json({ error: "Invalid email" }, 400);
  }

  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("INVITE_FROM_EMAIL") ?? Deno.env.get("PASSWORD_RESET_FROM_EMAIL");
  if (!resendApiKey || !fromEmail) {
    return json({ error: "Invitation email service is not configured" }, 503);
  }

  const appStoreUrl = (payload.app_store_url ?? "").trim() || Deno.env.get("INVITE_APP_STORE_URL") || "https://apps.apple.com/us/app/vineyard-tracker/id6761143377";
  const emailContent = renderEmail({
    vineyardName: payload.vineyard_name || "a vineyard",
    role: payload.role || "Member",
    invitedByName: payload.invited_by_name || "A VineTrack user",
    acceptUrl: appStoreUrl,
  });

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
    console.error("[send-invitation-email] Resend error", resendResponse.status, body);
    return json({ error: "Email provider rejected the request" }, 502);
  }

  const result = await resendResponse.json();
  return json({ ok: true, id: result.id ?? null });
});
