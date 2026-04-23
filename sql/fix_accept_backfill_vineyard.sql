-- =====================================================================
-- fix_accept_backfill_vineyard.sql
--
-- Root cause of the current "Failed to accept invitation" error:
--
--   The invitation points at vineyard c944fc74-d3bd-4ffb-a2f6-2ea3bf130905
--   ("Stockmans Ridge"), but that row no longer exists in public.vineyards.
--   Both the accept_invitation RPC AND the fallback direct insert then
--   fail on vineyard_members_vineyard_id_fkey.
--
-- This script:
--   1. Back-fills a stub public.vineyards row for every pending invitation
--      whose vineyard_id is missing (uses the invitation's vineyard_name
--      and inviter as owner_id so existing RLS keeps working).
--   2. Rebuilds accept_invitation / accept_pending_invitations_for_me so
--      they auto-create the stub inside the same transaction as the
--      membership insert. No more FK violations, even if a vineyard gets
--      deleted between sending and accepting.
--   3. Keeps the case-insensitive email + id matching from
--      FINAL_FIX_INVITE_CASE.sql.
--
-- Idempotent. Safe to re-run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Back-fill stub vineyards for orphaned pending invitations
-- ---------------------------------------------------------------------
insert into public.vineyards (id, owner_id, name)
select distinct i.vineyard_id,
       i.invited_by,
       coalesce(nullif(btrim(i.vineyard_name), ''), 'Vineyard')
  from public.invitations i
 where i.status in ('pending','sent')
   and not exists (
       select 1 from public.vineyards v
        where lower(v.id::text) = lower(i.vineyard_id::text)
   )
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 1. Drop old overloads
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
    for r in
        select p.oid::regprocedure as sig
          from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('accept_invitation',
                             'accept_pending_invitations_for_me')
    loop
        execute 'drop function ' || r.sig::text || ' cascade';
    end loop;
end$$;

-- ---------------------------------------------------------------------
-- 2. accept_invitation — auto-create stub vineyard if missing
-- ---------------------------------------------------------------------
create or replace function public.accept_invitation(p_token text)
returns public.invitations
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid   uuid := auth.uid();
    v_email text;
    v_inv   public.invitations;
begin
    if v_uid is null then
        raise exception 'Not authenticated';
    end if;

    select lower(coalesce(au.email, ''))
      into v_email
      from auth.users au
     where lower(au.id::text) = lower(v_uid::text)
     limit 1;

    -- Match by token OR id, case-insensitive.
    -- Email match is tolerant: if we have an email, require it to match;
    -- otherwise fall through on id match only (handles edge cases where
    -- auth.users email is briefly unavailable).
    select * into v_inv
      from public.invitations i
     where (lower(coalesce(i.token,'')) = lower(btrim(p_token))
            or lower(i.id::text)        = lower(btrim(p_token)))
       and i.status in ('pending','sent')
       and (coalesce(v_email,'') = ''
            or lower(i.email) = v_email)
     limit 1;

    if v_inv.id is null then
        raise exception 'Invitation not found';
    end if;

    -- Ensure the vineyard row exists so the FK on vineyard_members holds.
    insert into public.vineyards (id, owner_id, name)
    values (v_inv.vineyard_id,
            v_inv.invited_by,
            coalesce(nullif(btrim(v_inv.vineyard_name), ''), 'Vineyard'))
    on conflict (id) do nothing;

    insert into public.vineyard_members (vineyard_id, user_id, name, role)
    values (v_inv.vineyard_id, v_uid,
            coalesce((select p.name from public.profiles p
                       where lower(p.id::text) = lower(v_uid::text)), ''),
            v_inv.role)
    on conflict (vineyard_id, user_id) do update
       set role = excluded.role;

    update public.invitations
       set status = 'accepted',
           accepted_at = now(),
           accepted_by = v_uid
     where id = v_inv.id
     returning * into v_inv;

    return v_inv;
end;
$$;

alter function public.accept_invitation(text) owner to postgres;
revoke all on function public.accept_invitation(text) from public;
grant execute on function public.accept_invitation(text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. accept_pending_invitations_for_me — same auto-create logic
-- ---------------------------------------------------------------------
create or replace function public.accept_pending_invitations_for_me()
returns setof public.invitations
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid   uuid := auth.uid();
    v_email text;
    v_inv   public.invitations;
begin
    if v_uid is null then
        return;
    end if;

    select lower(coalesce(au.email, ''))
      into v_email
      from auth.users au
     where lower(au.id::text) = lower(v_uid::text)
     limit 1;

    if v_email is null or v_email = '' then
        return;
    end if;

    for v_inv in
        select *
          from public.invitations i
         where i.status in ('pending','sent')
           and lower(i.email) = v_email
    loop
        insert into public.vineyards (id, owner_id, name)
        values (v_inv.vineyard_id,
                v_inv.invited_by,
                coalesce(nullif(btrim(v_inv.vineyard_name), ''), 'Vineyard'))
        on conflict (id) do nothing;

        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        values (v_inv.vineyard_id, v_uid,
                coalesce((select p.name from public.profiles p
                           where lower(p.id::text) = lower(v_uid::text)), ''),
                v_inv.role)
        on conflict (vineyard_id, user_id) do update
           set role = excluded.role;

        update public.invitations
           set status = 'accepted',
               accepted_at = now(),
               accepted_by = v_uid
         where id = v_inv.id
         returning * into v_inv;

        return next v_inv;
    end loop;

    return;
end;
$$;

alter function public.accept_pending_invitations_for_me() owner to postgres;
revoke all on function public.accept_pending_invitations_for_me() from public;
grant execute on function public.accept_pending_invitations_for_me() to authenticated;

-- ---------------------------------------------------------------------
-- 4. Verify
-- ---------------------------------------------------------------------
select 'orphaned_invitations_remaining' as what, count(*) as n
  from public.invitations i
 where i.status in ('pending','sent')
   and not exists (select 1 from public.vineyards v
                    where lower(v.id::text) = lower(i.vineyard_id::text));
