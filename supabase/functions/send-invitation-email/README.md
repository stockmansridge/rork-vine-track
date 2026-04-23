# send-invitation-email

Supabase Edge Function that sends VineTrack invitation emails via Resend.

## One-time setup

1. Create a [Resend](https://resend.com) account and generate an API key.
2. Verify the sender domain in Resend (or use `onboarding@resend.dev` for quick tests).
3. In the Supabase Dashboard → **Project Settings → Edge Functions → Secrets**, add:
   - `RESEND_API_KEY` — your Resend API key (starts with `re_`)
   - `INVITE_FROM_EMAIL` — e.g. `VineTrack <noreply@yourdomain.com>`
   - `INVITE_APP_STORE_URL` — (optional) the App Store URL for VineTrack

## Deploy

From the repo root:

```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase functions deploy send-invitation-email
```

The iOS app invokes this function automatically whenever an invitation is
created or re-sent.

## Test manually

```bash
curl -X POST \
  "https://<project-ref>.supabase.co/functions/v1/send-invitation-email" \
  -H "Authorization: Bearer <your-anon-key>" \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","vineyard_name":"Test Vineyard","role":"Worker","invited_by_name":"Alice"}'
```
