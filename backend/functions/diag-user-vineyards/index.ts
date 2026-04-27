// deno-lint-ignore-file no-explicit-any
// @ts-ignore Deno runtime
declare const Deno: any;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

// @ts-ignore
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    return new Response(JSON.stringify({ error: "missing service role env" }), { status: 500, headers: CORS });
  }

  const reqUrl = new URL(req.url);
  let email = reqUrl.searchParams.get("email") ?? "";
  if (!email && req.method === "POST") {
    const body = await req.json().catch(() => ({}));
    email = (body.email ?? "").toString();
  }
  if (!email) email = "stockmansridge@gmail.com";

  const headers = { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" };

  const pRes = await fetch(`${url}/rest/v1/profiles?select=id,email,name,is_admin&email=ilike.${encodeURIComponent(email)}`, { headers });
  const profiles = await pRes.json();

  const out: any = { email, profiles, owned: [], memberOf: [], invitations: [], similarVineyards: [] };

  if (Array.isArray(profiles) && profiles.length) {
    const uid = profiles[0].id;
    const ownedRes = await fetch(`${url}/rest/v1/vineyards?select=id,name,owner_id,created_at&owner_id=eq.${uid}`, { headers });
    out.owned = await ownedRes.json();

    const memRes = await fetch(`${url}/rest/v1/vineyard_members?select=vineyard_id,role,name,joined_at&user_id=eq.${uid}`, { headers });
    const members = await memRes.json();
    if (Array.isArray(members) && members.length) {
      const ids = members.map((m: any) => `"${m.vineyard_id}"`).join(",");
      const vRes = await fetch(`${url}/rest/v1/vineyards?select=id,name,owner_id&id=in.(${ids})`, { headers });
      const vs = await vRes.json();
      out.memberOf = members.map((m: any) => ({ ...m, vineyard: (vs as any[]).find(v => v.id === m.vineyard_id) ?? null }));
    }

    const invRes = await fetch(`${url}/rest/v1/invitations?select=id,vineyard_id,vineyard_name,role,status,invited_by_name,created_at&email=ilike.${encodeURIComponent(email)}`, { headers });
    out.invitations = await invRes.json();
  }

  const sRes = await fetch(`${url}/rest/v1/vineyards?select=id,name,owner_id&or=(name.ilike.*stockman*,name.ilike.*ridge*)`, { headers });
  out.similarVineyards = await sRes.json();

  return new Response(JSON.stringify(out, null, 2), {
    headers: { ...CORS, "Content-Type": "application/json" },
  });
});
