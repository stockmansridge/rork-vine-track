-- =====================================================================
-- DEFINITIVE_FIX_RECURSION.sql
--
-- The "infinite recursion detected in policy for relation 'vineyards'"
-- error keeps coming back because some OTHER table's RLS policy inline-
-- queries vineyards or vineyard_members. When that policy is evaluated,
-- Postgres re-enters the vineyards/vineyard_members policies, which in
-- turn evaluate the other table again -> recursion.
--
-- Tables known to participate in the cycle in this project:
--   public.vineyards
--   public.vineyard_members
--   public.invitations
--   public.vineyard_data
--   public.audit_logs
--
-- THE ONLY SAFE FIX
--   1. One SECURITY DEFINER helper, owned by postgres, with
--      row_security = off. RLS can never re-enter it.
--   2. Drop EVERY policy on EVERY table above (discovered dynamically
--      from pg_policies so stale policies cannot survive).
--   3. Recreate policies that ONLY call the helper -- never an inline
--      subquery against another RLS-protected table.
--
-- HOW TO APPLY
--   Supabase Dashboard -> SQL Editor -> paste this whole file -> Run.
--   Idempotent: safe to run multiple times.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Helpers (postgres-owned, SECURITY DEFINER, row_security off).
-- ---------------------------------------------------------------------
drop function if exists public.is_vineyard_member(text)           cascade;
drop function if exists public.is_vineyard_member(uuid)           cascade;
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
-- 2. Drop EVERY policy on every participating table.
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
    for r in
        select schemaname, tablename, policyname
          from pg_policies
         where schemaname = 'public'
           and tablename in (
               'vineyards',
               'vineyard_members',
               'invitations',
               'vineyard_data',
               'audit_logs'
           )
    loop
        execute format('drop policy if exists %I on %I.%I',
                       r.policyname, r.schemaname, r.tablename);
    end loop;
end$$;

-- ---------------------------------------------------------------------
-- 3a. vineyards
-- ---------------------------------------------------------------------
alter table public.vineyards enable row level security;

create policy "vineyards_select_member"
    on public.vineyards for select to authenticated
    using ( public.is_vineyard_member(vineyards.id::text) );

create policy "vineyards_insert_owner"
    on public.vineyards for insert to authenticated
    with check ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) );

create policy "vineyards_update_owner"
    on public.vineyards for update to authenticated
    using      ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) )
    with check ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) );

create policy "vineyards_delete_owner"
    on public.vineyards for delete to authenticated
    using ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) );

-- ---------------------------------------------------------------------
-- 3b. vineyard_members
-- ---------------------------------------------------------------------
alter table public.vineyard_members enable row level security;

create policy "vineyard_members_select_same_vineyard"
    on public.vineyard_members for select to authenticated
    using ( public.is_vineyard_member(vineyard_members.vineyard_id::text) );

create policy "vineyard_members_insert_self_or_manager"
    on public.vineyard_members for insert to authenticated
    with check (
        lower(vineyard_members.user_id::text) = lower(auth.uid()::text)
        or public.is_vineyard_owner_or_manager(vineyard_members.vineyard_id::text)
    );

create policy "vineyard_members_update_manager"
    on public.vineyard_members for update to authenticated
    using      ( public.is_vineyard_owner_or_manager(vineyard_members.vineyard_id::text) )
    with check ( public.is_vineyard_owner_or_manager(vineyard_members.vineyard_id::text) );

create policy "vineyard_members_delete_self_or_manager"
    on public.vineyard_members for delete to authenticated
    using (
        lower(vineyard_members.user_id::text) = lower(auth.uid()::text)
        or public.is_vineyard_owner_or_manager(vineyard_members.vineyard_id::text)
    );

-- ---------------------------------------------------------------------
-- 3c. invitations
-- ---------------------------------------------------------------------
alter table public.invitations enable row level security;

create policy "invitations_select_invitee_or_manager"
    on public.invitations for select to authenticated
    using (
        lower(invitations.email) = lower(coalesce(auth.jwt() ->> 'email',''))
        or lower(invitations.invited_by::text) = lower(auth.uid()::text)
        or public.is_vineyard_owner_or_manager(invitations.vineyard_id::text)
    );

create policy "invitations_insert_owner_or_manager"
    on public.invitations for insert to authenticated
    with check (
        lower(invitations.invited_by::text) = lower(auth.uid()::text)
        and public.is_vineyard_owner_or_manager(invitations.vineyard_id::text)
    );

create policy "invitations_update_invitee_or_manager"
    on public.invitations for update to authenticated
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
    on public.invitations for delete to authenticated
    using ( public.is_vineyard_owner_or_manager(invitations.vineyard_id::text) );

-- ---------------------------------------------------------------------
-- 3d. vineyard_data  (THIS is the table whose old policies were
--     re-querying vineyards/vineyard_members and reintroducing the
--     recursion every time something rebuilt them.)
-- ---------------------------------------------------------------------
do $$
begin
    if to_regclass('public.vineyard_data') is not null then
        execute 'alter table public.vineyard_data enable row level security';

        execute $p$
            create policy "vineyard_data_select_member"
                on public.vineyard_data for select to authenticated
                using ( public.is_vineyard_member(vineyard_data.vineyard_id::text) )
        $p$;

        execute $p$
            create policy "vineyard_data_insert_member"
                on public.vineyard_data for insert to authenticated
                with check ( public.is_vineyard_member(vineyard_data.vineyard_id::text) )
        $p$;

        execute $p$
            create policy "vineyard_data_update_member"
                on public.vineyard_data for update to authenticated
                using      ( public.is_vineyard_member(vineyard_data.vineyard_id::text) )
                with check ( public.is_vineyard_member(vineyard_data.vineyard_id::text) )
        $p$;

        execute $p$
            create policy "vineyard_data_delete_member"
                on public.vineyard_data for delete to authenticated
                using ( public.is_vineyard_member(vineyard_data.vineyard_id::text) )
        $p$;
    end if;
end$$;

-- ---------------------------------------------------------------------
-- 3e. audit_logs (only if the table exists)
-- ---------------------------------------------------------------------
do $$
begin
    if to_regclass('public.audit_logs') is not null then
        execute 'alter table public.audit_logs enable row level security';

        execute $p$
            create policy "audit_logs_select_member"
                on public.audit_logs for select to authenticated
                using ( public.is_vineyard_member(audit_logs.vineyard_id::text) )
        $p$;

        execute $p$
            create policy "audit_logs_insert_member"
                on public.audit_logs for insert to authenticated
                with check ( public.is_vineyard_member(audit_logs.vineyard_id::text) )
        $p$;
    end if;
end$$;

-- ---------------------------------------------------------------------
-- 4. Verification: every policy on these tables must call ONLY the
--    helper functions -- never inline-query another RLS table.
-- ---------------------------------------------------------------------
select 'POLICIES' as section,
       tablename, policyname, cmd,
       qual          as using_expr,
       with_check    as check_expr
  from pg_policies
 where schemaname = 'public'
   and tablename in (
       'vineyards','vineyard_members','invitations',
       'vineyard_data','audit_logs'
   )
 order by tablename, policyname;

select 'FUNCTIONS' as section,
       p.oid::regprocedure::text as signature,
       pg_get_userbyid(p.proowner) as owner,
       case when p.prosecdef then 'SECURITY DEFINER'
            else 'SECURITY INVOKER' end as security,
       coalesce(
         (select string_agg(c, ', ') from unnest(p.proconfig) c),
         '(no config)') as proconfig
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('is_vineyard_member','is_vineyard_owner_or_manager');
