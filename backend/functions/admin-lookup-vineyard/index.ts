// deno-lint-ignore-file no-explicit-any
// @ts-ignore Deno runtime
declare const Deno: any;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// @ts-ignore
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    return new Response(JSON.stringify({ error: "missing service role env" }), { status: 500, headers: CORS });
  }

  const body = await req.json().catch(() => ({}));
  const search = body.search !== undefined ? body.search.toString() : "stockman";
  const listAll = body.all === true;

  const headers = { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" };

  const filter = listAll ? "" : `&name=ilike.*${encodeURIComponent(search)}*`;
  const vRes = await fetch(`${url}/rest/v1/vineyards?select=id,name,owner_id,country,created_at${filter}`, { headers });
  const vineyards = await vRes.json();

  const results: any[] = [];
  for (const v of vineyards) {
    const mRes = await fetch(`${url}/rest/v1/vineyard_members?select=user_id,name,role,joined_at&vineyard_id=eq.${v.id}`, { headers });
    const members = await mRes.json();
    const iRes = await fetch(`${url}/rest/v1/invitations?select=email,role,status,created_at,invited_by_name&vineyard_id=eq.${v.id}`, { headers });
    const invites = await iRes.json();

    let ownerProfile: any = null;
    if (v.owner_id) {
      const pRes = await fetch(`${url}/rest/v1/profiles?select=id,email,name&id=eq.${v.owner_id}`, { headers });
      const pArr = await pRes.json();
      ownerProfile = Array.isArray(pArr) && pArr.length ? pArr[0] : null;
    }

    const memberIds = members.map((m: any) => m.user_id).filter(Boolean);
    let memberProfiles: any[] = [];
    if (memberIds.length) {
      const idsCsv = memberIds.map((id: string) => `"${id}"`).join(",");
      const ppRes = await fetch(`${url}/rest/v1/profiles?select=id,email,name&id=in.(${idsCsv})`, { headers });
      memberProfiles = await ppRes.json();
    }

    results.push({ vineyard: v, owner: ownerProfile, members, memberProfiles, invitations: invites });
  }

  return new Response(JSON.stringify({ count: vineyards.length, results }, null, 2), {
    headers: { ...CORS, "Content-Type": "application/json" },
  });
});
