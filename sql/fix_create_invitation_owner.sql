-- =====================================================================
-- fix_create_invitation_owner.sql
--
-- Definitive fix for: "Not authorised to invite ... owner=f, manager=f"
--
-- The error means the create_invitation() RPC could not confirm that the
-- caller owns (or manages) the vineyard. This script:
--
--   1. Back-fills vineyards.owner_id from vineyard_members.
--   2. Inserts an 'Owner' row in vineyard_members for every vineyard owner.
--   3. Drops every overload of create_invitation() so only ONE version
--      exists and PostgREST cannot route to a stale one.
--   4. Recreates create_invitation() with a permissive owner/manager check
--      that trims whitespace and casts both sides to uuid (avoiding any
--      hidden text formatting issues).
--   5. Ensures RLS on invitations allows owners/managers to INSERT
--      directly as a fallback.
--   6. Prints a diagnostic snapshot so you can verify the repair.
--
-- HOW TO RUN: paste this whole file into the Supabase SQL Editor while
-- signed in as any user and press Run. It is idempotent — safe to run
-- multiple times.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Back-fill vineyards.owner_id from vineyard_members
-- ---------------------------------------------------------------------
update public.vineyards v
   set owner_id = vm.user_id
  from public.vineyard_members vm
 where vm.vineyard_id = v.id
   and vm.role = 'Owner'
   and (v.owner_id is null
        or lower(v.owner_id::text) <> lower(vm.user_id::text));

-- ---------------------------------------------------------------------
-- 2. Insert Owner member row wherever the owner isn't already a member
-- ---------------------------------------------------------------------
insert into public.vineyard_members (vineyard_id, user_id, name, role)
select v.id,
       v.owner_id,
       coalesce((select p.name from public.profiles p where p.id = v.owner_id), ''),
       'Owner'
  from public.vineyards v
 where v.owner_id is not null
   and not exists (
         select 1 from public.vineyard_members vm
          where vm.vineyard_id = v.id
            and lower(vm.user_id::text) = lower(v.owner_id::text)
       )
on conflict (vineyard_id, user_id) do update
   set role = 'Owner'
 where public.vineyard_members.role not in ('Owner','Manager');

-- ---------------------------------------------------------------------
-- 3. Drop ALL overloads of create_invitation so no stale one lingers
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
    for r in
        select p.oid::regprocedure as sig
          from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname = 'create_invitation'
    loop
        execute 'drop function ' || r.sig::text || ' cascade';
    end loop;
end$$;

-- ---------------------------------------------------------------------
-- 4. Recreate create_invitation with robust auth check
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
    v_uid        uuid := auth.uid();
    v_vid        uuid := nullif(btrim(p_vineyard_id), '')::uuid;
    v_is_owner   boolean := false;
    v_is_manager boolean := false;
    v_row        public.invitations;
begin
    if v_uid is null then
        raise exception 'Not authenticated';
    end if;
    if v_vid is null then
        raise exception 'Vineyard id is required';
    end if;

    select exists (
        select 1 from public.vineyards v
         where v.id = v_vid
           and v.owner_id = v_uid
    ) into v_is_owner;

    select exists (
        select 1 from public.vineyard_members vm
         where vm.vineyard_id = v_vid
           and vm.user_id = v_uid
           and vm.role in ('Owner','Manager')
    ) into v_is_manager;

    if not (v_is_owner or v_is_manager) then
        raise exception 'Not authorised to invite (uid=%, vineyard=%, owner=%, manager=%)',
            v_uid, v_vid, v_is_owner, v_is_manager;
    end if;

    insert into public.invitations
        (vineyard_id, vineyard_name, email, role, invited_by, invited_by_name, status)
    values
        (v_vid, p_vineyard_name, lower(btrim(p_email)),
         p_role, v_uid, p_invited_by_name, 'pending')
    returning * into v_row;

    return v_row;
end;
$$;

alter function public.create_invitation(text,text,text,text,text) owner to postgres;
revoke all on function public.create_invitation(text,text,text,text,text) from public;
grant execute on function public.create_invitation(text,text,text,text,text) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Ensure invitations RLS allows owners/managers to INSERT directly
--    (fallback path if the RPC ever fails)
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
         where v.id = invitations.vineyard_id
           and v.owner_id = auth.uid()
    )
    or exists (
        select 1 from public.vineyard_members vm
         where vm.vineyard_id = invitations.vineyard_id
           and vm.user_id = auth.uid()
           and vm.role in ('Owner','Manager')
    )
);

drop policy if exists "invitations_select_visible" on public.invitations;
create policy "invitations_select_visible"
on public.invitations
for select
to authenticated
using (
    lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
    or invited_by = auth.uid()
    or exists (
        select 1 from public.vineyards v
         where v.id = invitations.vineyard_id
           and v.owner_id = auth.uid()
    )
    or exists (
        select 1 from public.vineyard_members vm
         where vm.vineyard_id = invitations.vineyard_id
           and vm.user_id = auth.uid()
           and vm.role in ('Owner','Manager')
    )
);

drop policy if exists "invitations_update_owner_or_invitee" on public.invitations;
create policy "invitations_update_owner_or_invitee"
on public.invitations
for update
to authenticated
using (
    lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
    or invited_by = auth.uid()
    or exists (
        select 1 from public.vineyards v
         where v.id = invitations.vineyard_id
           and v.owner_id = auth.uid()
    )
    or exists (
        select 1 from public.vineyard_members vm
         where vm.vineyard_id = invitations.vineyard_id
           and vm.user_id = auth.uid()
           and vm.role in ('Owner','Manager')
    )
);

-- ---------------------------------------------------------------------
-- 6. Diagnostic snapshot — confirm repair
-- ---------------------------------------------------------------------
select 'VINEYARDS' as section,
       v.id::text                                            as vineyard_id,
       v.name,
       v.owner_id::text                                      as owner_id,
       (select count(*) from public.vineyard_members vm
         where vm.vineyard_id = v.id)                        as member_count,
       (select string_agg(vm.user_id::text || ':' || vm.role, ', ')
          from public.vineyard_members vm
         where vm.vineyard_id = v.id)                        as members
  from public.vineyards v
 order by v.created_at;

select 'FUNCTIONS' as section,
       p.oid::regprocedure::text as signature,
       pg_get_userbyid(p.proowner) as owner,
       case when p.prosecdef then 'SECURITY DEFINER' else 'SECURITY INVOKER' end as security
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'create_invitation';
