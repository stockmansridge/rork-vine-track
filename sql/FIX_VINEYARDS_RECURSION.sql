-- =====================================================================
-- FIX_VINEYARDS_RECURSION.sql
--
-- Error in app:
--   "Couldn't load invitations: infinite recursion detected in policy
--    for relation 'vineyards'"
--
-- ROOT CAUSE
--   The `invitations` SELECT/UPDATE/DELETE policies, the `vineyards`
--   SELECT policy, and the `vineyard_members` SELECT policy all read
--   each other's tables. Whenever ONE of them is rebuilt without using
--   a SECURITY DEFINER bypass (or the helper function gets recreated
--   without SECURITY DEFINER, or owned by a role that does not have
--   BYPASSRLS), Postgres re-enters the same policy while evaluating it
--   and bails out with the recursion error.
--
-- THE FIX
--   1. Rebuild the membership helper as a SECURITY DEFINER function
--      OWNED BY postgres AND with `set row_security = off`. That makes
--      it impossible for the helper to ever trigger RLS on the tables
--      it reads, regardless of who calls it.
--   2. Drop EVERY existing policy on `vineyards`, `vineyard_members`,
--      and `invitations` (idempotent — uses pg_policies to find them).
--   3. Recreate the policies so that:
--        - `vineyards`           → uses the helper (no inline subquery)
--        - `vineyard_members`    → uses the helper (no inline subquery)
--        - `invitations`         → uses the helper (no inline subquery)
--      No policy queries another RLS-protected table directly. The
--      recursion cycle is broken.
--
-- HOW TO APPLY
--   Supabase Dashboard → SQL Editor → paste this whole file → Run.
--   Idempotent: safe to run multiple times.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Helper function — single source of truth for "can this user see
--    this vineyard?". Owned by postgres (BYPASSRLS) and with
--    row_security = off, so it can never recurse into RLS.
-- ---------------------------------------------------------------------
drop function if exists public.is_vineyard_member(text)         cascade;
drop function if exists public.is_vineyard_member(uuid)         cascade;
drop function if exists public.is_vineyard_owner_or_manager(text) cascade;
drop function if exists public.is_vineyard_owner_or_manager(uuid) cascade;

create or replace function public.is_vineyard_member(p_vineyard_id text)
returns boolean
language sql
security definer
set search_path = public
set row_security = off
stable
as $$
    select exists (
        select 1
          from public.vineyard_members vm
         where lower(vm.vineyard_id::text) = lower(p_vineyard_id)
           and lower(vm.user_id::text)     = lower(auth.uid()::text)
    )
    or exists (
        select 1
          from public.vineyards v
         where lower(v.id::text)       = lower(p_vineyard_id)
           and lower(v.owner_id::text) = lower(auth.uid()::text)
    );
$$;

alter function public.is_vineyard_member(text) owner to postgres;
revoke all on function public.is_vineyard_member(text) from public;
grant execute on function public.is_vineyard_member(text) to authenticated;

create or replace function public.is_vineyard_owner_or_manager(p_vineyard_id text)
returns boolean
language sql
security definer
set search_path = public
set row_security = off
stable
as $$
    select exists (
        select 1
          from public.vineyards v
         where lower(v.id::text)       = lower(p_vineyard_id)
           and lower(v.owner_id::text) = lower(auth.uid()::text)
    )
    or exists (
        select 1
          from public.vineyard_members vm
         where lower(vm.vineyard_id::text) = lower(p_vineyard_id)
           and lower(vm.user_id::text)     = lower(auth.uid()::text)
           and vm.role in ('Owner','Manager')
    );
$$;

alter function public.is_vineyard_owner_or_manager(text) owner to postgres;
revoke all on function public.is_vineyard_owner_or_manager(text) from public;
grant execute on function public.is_vineyard_owner_or_manager(text) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Drop EVERY existing policy on the three relations so no stale,
--    recursive policy can survive. We discover them dynamically from
--    pg_policies — no need to remember every old name.
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
    for r in
        select schemaname, tablename, policyname
          from pg_policies
         where schemaname = 'public'
           and tablename in ('vineyards', 'vineyard_members', 'invitations')
    loop
        execute format('drop policy if exists %I on %I.%I',
                       r.policyname, r.schemaname, r.tablename);
    end loop;
end$$;

-- ---------------------------------------------------------------------
-- 3a. vineyards — SELECT via helper, writes by owner only
-- ---------------------------------------------------------------------
alter table public.vineyards enable row level security;

create policy "vineyards_select_member"
    on public.vineyards
    for select
    to authenticated
    using ( public.is_vineyard_member(vineyards.id::text) );

create policy "vineyards_insert_owner"
    on public.vineyards
    for insert
    to authenticated
    with check ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) );

create policy "vineyards_update_owner"
    on public.vineyards
    for update
    to authenticated
    using      ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) )
    with check ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) );

create policy "vineyards_delete_owner"
    on public.vineyards
    for delete
    to authenticated
    using ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) );

-- ---------------------------------------------------------------------
-- 3b. vineyard_members — SELECT via helper, manager writes via helper.
--     The "insert self" branch lets the accept-invite RPC fall back to
--     a direct insert without elevated rights.
-- ---------------------------------------------------------------------
alter table public.vineyard_members enable row level security;

create policy "vineyard_members_select_same_vineyard"
    on public.vineyard_members
    for select
    to authenticated
    using ( public.is_vineyard_member(vineyard_members.vineyard_id::text) );

create policy "vineyard_members_insert_self_or_manager"
    on public.vineyard_members
    for insert
    to authenticated
    with check (
        lower(vineyard_members.user_id::text) = lower(auth.uid()::text)
        or public.is_vineyard_owner_or_manager(vineyard_members.vineyard_id::text)
    );

create policy "vineyard_members_update_manager"
    on public.vineyard_members
    for update
    to authenticated
    using      ( public.is_vineyard_owner_or_manager(vineyard_members.vineyard_id::text) )
    with check ( public.is_vineyard_owner_or_manager(vineyard_members.vineyard_id::text) );

create policy "vineyard_members_delete_self_or_manager"
    on public.vineyard_members
    for delete
    to authenticated
    using (
        lower(vineyard_members.user_id::text) = lower(auth.uid()::text)
        or public.is_vineyard_owner_or_manager(vineyard_members.vineyard_id::text)
    );

-- ---------------------------------------------------------------------
-- 3c. invitations — invitee sees by email, owner/manager via helper.
--     No more inline subqueries against vineyards or vineyard_members.
-- ---------------------------------------------------------------------
alter table public.invitations enable row level security;

create policy "invitations_select_invitee_or_manager"
    on public.invitations
    for select
    to authenticated
    using (
        lower(invitations.email) = lower(coalesce(auth.jwt() ->> 'email',''))
        or lower(invitations.invited_by::text) = lower(auth.uid()::text)
        or public.is_vineyard_owner_or_manager(invitations.vineyard_id::text)
    );

create policy "invitations_insert_owner_or_manager"
    on public.invitations
    for insert
    to authenticated
    with check (
        lower(invitations.invited_by::text) = lower(auth.uid()::text)
        and public.is_vineyard_owner_or_manager(invitations.vineyard_id::text)
    );

create policy "invitations_update_invitee_or_manager"
    on public.invitations
    for update
    to authenticated
    using (
        lower(invitations.email) = lower(coalesce(auth.jwt() ->> 'email',''))
        or lower(invitations.invited_by::text) = lower(auth.uid()::text)
        or public.is_vineyard_owner_or_manager(invitations.vineyard_id::text)
    )
    with check (
        lower(invitations.email) = lower(coalesce(auth.jwt() ->> 'email',''))
        or lower(invitations.invited_by::text) = lower(auth.uid()::text)
        or public.is_vineyard_owner_or_manager(invitations.vineyard_id::text)
    );

create policy "invitations_delete_manager"
    on public.invitations
    for delete
    to authenticated
    using ( public.is_vineyard_owner_or_manager(invitations.vineyard_id::text) );

-- ---------------------------------------------------------------------
-- 4. Verify — list every policy left on the three tables and confirm
--    the helper functions are SECURITY DEFINER owned by postgres.
-- ---------------------------------------------------------------------
select 'POLICIES' as section,
       schemaname, tablename, policyname, cmd, roles
  from pg_policies
 where schemaname = 'public'
   and tablename in ('vineyards','vineyard_members','invitations')
 order by tablename, policyname;

select 'FUNCTIONS' as section,
       p.oid::regprocedure::text                                as signature,
       pg_get_userbyid(p.proowner)                              as owner,
       case when p.prosecdef then 'SECURITY DEFINER'
            else 'SECURITY INVOKER' end                          as security,
       coalesce(
         (select string_agg(c, ', ')
            from unnest(p.proconfig) c),
         '(no config)')                                          as proconfig
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('is_vineyard_member','is_vineyard_owner_or_manager');
