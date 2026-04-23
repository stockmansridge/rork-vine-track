-- =====================================================================
-- FINAL_FIX_INVITE_CASE.sql
--
-- Root cause of the "Not authorised to invite (owner=f, manager=f)" loop:
--
--   iOS stores UUIDs as UPPERCASE text ("C944FC74-..."), but the app
--   sends LOWERCASE ("c944fc74-...") when calling the RPC. Every
--   previous fix compared `v.id::text = p_vineyard_id` without
--   lower()-ing BOTH sides, so the vineyard row was never found and
--   owner/manager both returned false — even though the data is fine.
--
-- This file:
--   1. Drops every overload of create_invitation (and accept_invitation).
--   2. Rebuilds create_invitation with lower() on BOTH sides of every
--      id comparison (vineyard_id AND owner/user_id).
--   3. Rebuilds accept_invitation / accept_pending_invitations_for_me
--      the same way, resolving email from auth.users (not the JWT).
--   4. Back-fills missing Owner membership rows.
--   5. Runs a live self-test that proves the current user can pass the
--      auth check for every vineyard they own.
--
-- Idempotent. Safe to run multiple times.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Back-fill owner_id + Owner membership rows (safety net)
-- ---------------------------------------------------------------------
update public.vineyards v
   set owner_id = vm.user_id
  from public.vineyard_members vm
 where lower(vm.vineyard_id::text) = lower(v.id::text)
   and vm.role = 'Owner'
   and (v.owner_id is null
        or lower(v.owner_id::text) <> lower(vm.user_id::text));

insert into public.vineyard_members (vineyard_id, user_id, name, role)
select v.id,
       v.owner_id,
       coalesce((select p.name from public.profiles p
                  where lower(p.id::text) = lower(v.owner_id::text)), ''),
       'Owner'
  from public.vineyards v
 where v.owner_id is not null
   and not exists (
         select 1 from public.vineyard_members vm
          where lower(vm.vineyard_id::text) = lower(v.id::text)
            and lower(vm.user_id::text)    = lower(v.owner_id::text)
       )
on conflict (vineyard_id, user_id) do update
   set role = 'Owner'
 where public.vineyard_members.role not in ('Owner','Manager');

-- ---------------------------------------------------------------------
-- 1. Drop every overload of create_invitation and accept_invitation
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
    for r in
        select p.oid::regprocedure as sig
          from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('create_invitation',
                             'accept_invitation',
                             'accept_pending_invitations_for_me')
    loop
        execute 'drop function ' || r.sig::text || ' cascade';
    end loop;
end$$;

-- ---------------------------------------------------------------------
-- 2. create_invitation — case-insensitive id matching on BOTH sides
-- ---------------------------------------------------------------------
create or replace function public.create_invitation(
    p_vineyard_id     text,
    p_vineyard_name   text,
    p_email           text,
    p_role            text,
    p_invited_by_name text
)
returns public.invitations
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid_txt    text := lower(coalesce(auth.uid()::text, ''));
    v_vid_txt    text := lower(btrim(coalesce(p_vineyard_id, '')));
    v_is_owner   boolean := false;
    v_is_manager boolean := false;
    v_row        public.invitations;
begin
    if v_uid_txt = '' then
        raise exception 'Not authenticated';
    end if;
    if v_vid_txt = '' then
        raise exception 'Vineyard id is required';
    end if;

    select exists (
        select 1 from public.vineyards v
         where lower(v.id::text)       = v_vid_txt
           and lower(v.owner_id::text) = v_uid_txt
    ) into v_is_owner;

    select exists (
        select 1 from public.vineyard_members vm
         where lower(vm.vineyard_id::text) = v_vid_txt
           and lower(vm.user_id::text)     = v_uid_txt
           and vm.role in ('Owner','Manager')
    ) into v_is_manager;

    if not (v_is_owner or v_is_manager) then
        raise exception 'Not authorised to invite (uid=%, vineyard=%, owner=%, manager=%)',
            v_uid_txt, v_vid_txt, v_is_owner, v_is_manager;
    end if;

    insert into public.invitations
        (vineyard_id, vineyard_name, email, role, invited_by, invited_by_name, status)
    values
        (v_vid_txt::uuid, p_vineyard_name, lower(btrim(p_email)),
         p_role, v_uid_txt::uuid, p_invited_by_name, 'pending')
    returning * into v_row;

    return v_row;
end;
$$;

alter function public.create_invitation(text,text,text,text,text) owner to postgres;
revoke all on function public.create_invitation(text,text,text,text,text) from public;
grant execute on function public.create_invitation(text,text,text,text,text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. accept_invitation — resolve email from auth.users, lower() on both
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

    select * into v_inv
      from public.invitations i
     where (lower(i.token) = lower(btrim(p_token))
            or lower(i.id::text) = lower(btrim(p_token)))
       and i.status in ('pending','sent')
       and lower(i.email) = coalesce(v_email,'')
     limit 1;

    if v_inv.id is null then
        raise exception 'Invitation not found for this account';
    end if;

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
-- 4. accept_pending_invitations_for_me — same fix
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
-- 5. RLS fallback policies (case-insensitive)
-- ---------------------------------------------------------------------
alter table public.invitations enable row level security;

drop policy if exists "invitations_insert_owner_or_manager" on public.invitations;
create policy "invitations_insert_owner_or_manager"
on public.invitations
for insert
to authenticated
with check (
    exists (
        select 1 from public.vineyards v
         where lower(v.id::text)       = lower(invitations.vineyard_id::text)
           and lower(v.owner_id::text) = lower(auth.uid()::text)
    )
    or exists (
        select 1 from public.vineyard_members vm
         where lower(vm.vineyard_id::text) = lower(invitations.vineyard_id::text)
           and lower(vm.user_id::text)     = lower(auth.uid()::text)
           and vm.role in ('Owner','Manager')
    )
);

-- ---------------------------------------------------------------------
-- 6. SELF-TEST — proves the current user can invite on their vineyards
-- ---------------------------------------------------------------------
select 'SELF_TEST' as phase,
       lower(auth.uid()::text)             as my_uid,
       lower(v.id::text)                   as vineyard_id,
       v.name,
       lower(v.owner_id::text)             as owner_id,
       (lower(v.owner_id::text) = lower(auth.uid()::text)) as owner_match,
       exists (
           select 1 from public.vineyard_members vm
            where lower(vm.vineyard_id::text) = lower(v.id::text)
              and lower(vm.user_id::text)     = lower(auth.uid()::text)
              and vm.role in ('Owner','Manager')
       )                                    as manager_match
  from public.vineyards v
 where lower(v.owner_id::text) = lower(auth.uid()::text)
    or exists (
         select 1 from public.vineyard_members vm
          where lower(vm.vineyard_id::text) = lower(v.id::text)
            and lower(vm.user_id::text)     = lower(auth.uid()::text)
       )
 order by v.created_at;
