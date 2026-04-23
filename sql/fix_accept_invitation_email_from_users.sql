-- =====================================================================
-- Fix invitation acceptance: resolve the signed-in user's email from
-- auth.users (via auth.uid()) instead of relying on auth.jwt() ->> 'email'.
--
-- WHY:
--   Some access tokens arrive without an `email` claim in the JWT (for
--   example OIDC sign-ins or sessions that were refreshed without the
--   original claim). When that happens `auth.jwt() ->> 'email'` returns
--   NULL/empty and every acceptance failed with
--     "Invitation is for foo@bar.com but you are signed in as "
--   or silently no-oped in the bulk accept.
--
--   This patch resolves the email by looking up auth.users by auth.uid(),
--   which works regardless of the JWT claim shape.
--
-- HOW TO APPLY:
--   1. Open Supabase Dashboard -> SQL Editor
--   2. Paste this ENTIRE file and click "Run"
-- =====================================================================

drop function if exists public.accept_invitation(uuid);
drop function if exists public.accept_invitation(text);
drop function if exists public.accept_pending_invitations_for_me();

-- ---------- accept_invitation(p_invitation_id) ------------------------
create or replace function public.accept_invitation(p_invitation_id text)
returns public.vineyard_members
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    v_uid   text := lower(auth.uid()::text);
    v_email text;
    v_inv   public.invitations;
    v_name  text;
    v_row   public.vineyard_members;
begin
    if v_uid is null or v_uid = '' then
        raise exception 'Not authenticated';
    end if;

    -- Resolve email from auth.users so we don't depend on JWT claims.
    select lower(coalesce(au.email, ''))
      into v_email
      from auth.users au
     where lower(au.id::text) = v_uid
     limit 1;

    if v_email is null or v_email = '' then
        -- Fallback: try the JWT claim if auth.users lookup missed.
        v_email := lower(coalesce(auth.jwt() ->> 'email', ''));
    end if;

    select * into v_inv
      from public.invitations
     where id::text = p_invitation_id
     limit 1;

    if v_inv.id is null then
        raise exception 'Invitation not found: %', p_invitation_id;
    end if;

    if not exists (select 1 from public.vineyards v where v.id::text = v_inv.vineyard_id::text) then
        update public.invitations set status = 'cancelled' where id = v_inv.id;
        raise exception 'The vineyard for this invitation no longer exists';
    end if;

    if v_email = '' or lower(v_inv.email) <> v_email then
        raise exception 'This invitation (%) is for % but you are signed in as %',
            p_invitation_id, v_inv.email, v_email;
    end if;

    select coalesce(
        (select p.name  from public.profiles p where p.id::text = v_uid),
        (select au.raw_user_meta_data ->> 'full_name' from auth.users au where au.id::text = v_uid),
        split_part(v_email, '@', 1)
    ) into v_name;

    insert into public.vineyard_members (vineyard_id, user_id, name, role)
    values (v_inv.vineyard_id, v_uid, coalesce(v_name, ''), v_inv.role)
    on conflict (vineyard_id, user_id)
    do update set role = excluded.role,
                  name = coalesce(nullif(excluded.name, ''), public.vineyard_members.name)
    returning * into v_row;

    update public.invitations
       set status = 'accepted'
     where id = v_inv.id;

    -- Any other pending invitation rows for the same vineyard+email are
    -- now stale; mark them cancelled so the UI only shows one active row.
    update public.invitations
       set status = 'cancelled'
     where vineyard_id = v_inv.vineyard_id
       and lower(email) = v_email
       and id <> v_inv.id
       and status = 'pending';

    return v_row;
end;
$$;

alter function public.accept_invitation(text) owner to postgres;
revoke all on function public.accept_invitation(text) from public;
grant execute on function public.accept_invitation(text) to authenticated;

-- ---------- accept_pending_invitations_for_me() -----------------------
create or replace function public.accept_pending_invitations_for_me()
returns integer
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    v_uid   text := lower(auth.uid()::text);
    v_email text;
    v_count integer := 0;
    v_inv   public.invitations;
    v_name  text;
begin
    if v_uid is null or v_uid = '' then
        return 0;
    end if;

    -- Resolve email from auth.users (primary source).
    select lower(coalesce(au.email, ''))
      into v_email
      from auth.users au
     where lower(au.id::text) = v_uid
     limit 1;

    if v_email is null or v_email = '' then
        v_email := lower(coalesce(auth.jwt() ->> 'email', ''));
    end if;

    if v_email is null or v_email = '' then
        return 0;
    end if;

    select coalesce(
        (select p.name  from public.profiles p where p.id::text = v_uid),
        (select au.raw_user_meta_data ->> 'full_name' from auth.users au where au.id::text = v_uid),
        split_part(v_email, '@', 1)
    ) into v_name;

    for v_inv in
        select i.* from public.invitations i
         where lower(i.email) = v_email
           and i.status = 'pending'
           and exists (select 1 from public.vineyards v where v.id::text = i.vineyard_id::text)
    loop
        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        values (v_inv.vineyard_id, v_uid, coalesce(v_name, ''), v_inv.role)
        on conflict (vineyard_id, user_id)
        do update set role = excluded.role,
                      name = coalesce(nullif(excluded.name, ''), public.vineyard_members.name);

        update public.invitations
           set status = 'accepted'
         where id = v_inv.id;

        -- Cancel any duplicate pending invites for the same vineyard+email.
        update public.invitations
           set status = 'cancelled'
         where vineyard_id = v_inv.vineyard_id
           and lower(email) = v_email
           and id <> v_inv.id
           and status = 'pending';

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$$;

alter function public.accept_pending_invitations_for_me() owner to postgres;
revoke all on function public.accept_pending_invitations_for_me() from public;
grant execute on function public.accept_pending_invitations_for_me() to authenticated;

-- ---------- One-shot backfill: accept every pending invitation whose --
-- email matches an existing auth user. Safe to run repeatedly. --------
do $$
declare
    v_inv   record;
    v_uid   text;
    v_name  text;
begin
    for v_inv in
        select i.*
          from public.invitations i
         where i.status = 'pending'
           and exists (select 1 from public.vineyards v where v.id::text = i.vineyard_id::text)
    loop
        select lower(au.id::text) into v_uid
          from auth.users au
         where lower(au.email) = lower(v_inv.email)
         limit 1;

        if v_uid is null then
            continue;
        end if;

        select coalesce(
            (select p.name  from public.profiles p where p.id::text = v_uid),
            (select au.raw_user_meta_data ->> 'full_name' from auth.users au where au.id::text = v_uid),
            split_part(v_inv.email, '@', 1)
        ) into v_name;

        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        values (v_inv.vineyard_id, v_uid, coalesce(v_name, ''), v_inv.role)
        on conflict (vineyard_id, user_id) do nothing;

        update public.invitations set status = 'accepted' where id = v_inv.id;
    end loop;
end $$;

-- ---------- De-duplicate: keep one active invite per (vineyard,email) --
update public.invitations i
   set status = 'cancelled'
  from (
      select id,
             row_number() over (
                 partition by vineyard_id, lower(email)
                 order by created_at desc nulls last, id desc
             ) as rn
        from public.invitations
       where status = 'pending'
  ) ranked
 where i.id = ranked.id
   and ranked.rn > 1;

-- ---------- Sanity ----------------------------------------------------
select 'vineyard_members rows' as what, count(*) as n from public.vineyard_members
union all
select 'pending invitations remaining', count(*) from public.invitations where status = 'pending'
union all
select 'accepted invitations', count(*) from public.invitations where status = 'accepted'
union all
select 'cancelled invitations', count(*) from public.invitations where status = 'cancelled';
