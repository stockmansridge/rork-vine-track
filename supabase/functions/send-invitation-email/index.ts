// Supabase Edge Function: send-invitation-email
// Sends an invitation email via Resend (https://resend.com).
//
// Required environment variables (set in Supabase Dashboard → Edge Functions → Secrets):
//   - RESEND_API_KEY        (e.g. re_xxxxxxxx)
//   - INVITE_FROM_EMAIL     (e.g. "VineTrack <noreply@yourdomain.com>")
//   - INVITE_APP_STORE_URL  (optional, fallback "Accept Invitation" URL)
//
// Deploy:
//   supabase functions deploy send-invitation-email --no-verify-jwt=false
//
// Invoked from the iOS app after an invitation row is inserted.

// deno-lint-ignore-file no-explicit-any
// @ts-ignore Deno runtime
declare const Deno: any;

interface InvitePayload {
  email: string;
  vineyard_name?: string;
  role?: string;
  invited_by_name?: string;
  invitation_id?: string;
}

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function renderEmail(p: {
  vineyardName: string;
  role: string;
  invitedByName: string;
  acceptUrl: string;
}): { subject: string; html: string; text: string } {
  const subject = `You've been invited to ${p.vineyardName} on VineTrack`;

  const html = `<!doctype html>
<html>
  <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;background:#f6f6f4;margin:0;padding:24px;color:#1c1c1e;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:520px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.05);">
      <tr>
        <td style="padding:32px 32px 16px 32px;">
          <div style="font-size:14px;color:#6e6e73;letter-spacing:0.04em;text-transform:uppercase;font-weight:600;">VineTrack</div>
          <h1 style="margin:12px 0 8px 0;font-size:26px;line-height:1.2;font-weight:700;color:#1c1c1e;">
            You've been invited to ${escapeHtml(p.vineyardName)}
          </h1>
          <p style="margin:0;font-size:16px;line-height:1.5;color:#3a3a3c;">
            ${escapeHtml(p.invitedByName)} invited you to join <strong>${escapeHtml(p.vineyardName)}</strong> as <strong>${escapeHtml(p.role)}</strong>.
          </p>
        </td>
      </tr>
      <tr>
        <td style="padding:8px 32px 24px 32px;">
          <a href="${p.acceptUrl}"
             style="display:inline-block;background:#5d3a7e;color:#ffffff;text-decoration:none;padding:14px 24px;border-radius:12px;font-weight:600;font-size:16px;">
            Accept Invitation
          </a>
          <p style="margin:20px 0 0 0;font-size:14px;line-height:1.5;color:#6e6e73;">
            Open VineTrack and sign in with <strong>${escapeHtml(p.acceptUrl.includes("@") ? "" : "")}</strong>this email address to accept. If you don't have the app yet, tap the button above to install it.
          </p>
        </td>
      </tr>
      <tr>
        <td style="padding:16px 32px 32px 32px;border-top:1px solid #e5e5ea;">
          <p style="margin:0;font-size:12px;color:#8e8e93;line-height:1.5;">
            If you weren't expecting this invitation, you can safely ignore this email.
          </p>
        </td>
      </tr>
    </table>
  </body>
</html>`;

  const text = `You've been invited to ${p.vineyardName} on VineTrack

${p.invitedByName} invited you to join ${p.vineyardName} as ${p.role}.

Accept the invitation: ${p.acceptUrl}

Open VineTrack and sign in with this email address to accept. If you weren't expecting this invitation, you can safely ignore this email.`;

  return { subject, html, text };
}

// @ts-ignore Deno runtime serve
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
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

  const email = (payload.email || "").trim().toLowerCase();
  if (!email) {
    return json({ error: "Missing 'email'" }, 400);
  }

  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("INVITE_FROM_EMAIL");
  if (!apiKey || !from) {
    return json(
      { error: "Server not configured: set RESEND_API_KEY and INVITE_FROM_EMAIL secrets." },
      500,
    );
  }

  const appStoreUrl =
    Deno.env.get("INVITE_APP_STORE_URL") || "https://apps.apple.com/";

  const vineyardName = payload.vineyard_name || "a vineyard";
  const role = payload.role || "Member";
  const invitedByName = payload.invited_by_name || "A VineTrack user";

  const { subject, html, text } = renderEmail({
    vineyardName,
    role,
    invitedByName,
    acceptUrl: appStoreUrl,
  });

  const resendRes = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [email],
      subject,
      html,
      text,
    }),
  });

  if (!resendRes.ok) {
    const body = await resendRes.text();
    console.error("[send-invitation-email] Resend error:", resendRes.status, body);
    return json(
      { error: "Email provider rejected the request", detail: body },
      resendRes.status,
    );
  }

  const result = await resendRes.json();
  return json({ ok: true, id: result.id ?? null });
});
