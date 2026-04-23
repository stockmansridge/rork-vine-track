-- =====================================================================
-- Fix Member Visibility RLS
--
-- PROBLEM:
--   Invited users now get a row in vineyard_members (the accept flow
--   works), but they still can't see the vineyard in the app, and the
--   owner still can't see the invited user in the members list.
--
-- ROOT CAUSE:
--   RLS on `vineyards`, `vineyard_members`, and `vineyard_data` only
--   allows the OWNER to SELECT. Non-owner members pass the membership
--   check in `vineyard_members` for their own row only, so:
--     - App queries vineyard_members WHERE user_id = me  -> OK (own row)
--     - App queries vineyards WHERE id = <vineyard>      -> BLOCKED
--     - App queries vineyard_data WHERE vineyard_id = X  -> BLOCKED
--   The owner also can't see OTHER members' rows because the policy
--   only permits `user_id = auth.uid()`.
--
-- FIX:
--   For each of the three tables, allow SELECT (and for vineyard_data
--   also INSERT/UPDATE/DELETE) to anyone who has a row in
--   vineyard_members for that vineyard. Owner keeps full control.
--
-- HOW TO APPLY:
--   1. Supabase Dashboard -> SQL Editor
--   2. Paste this ENTIRE file
--   3. Run
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helper: is the current user a member of the given vineyard?
-- SECURITY DEFINER so it can read vineyard_members without recursing
-- through that table's own RLS policies.
-- ---------------------------------------------------------------------
create or replace function public.is_vineyard_member(p_vineyard_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1
          from public.vineyard_members vm
         where vm.vineyard_id::text = p_vineyard_id
           and lower(vm.user_id::text) = lower(auth.uid()::text)
    )
    or exists (
        select 1
          from public.vineyards v
         where v.id::text = p_vineyard_id
           and lower(v.owner_id::text) = lower(auth.uid()::text)
    );
$$;

grant execute on function public.is_vineyard_member(text) to authenticated;

-- =====================================================================
-- vineyards
-- =====================================================================
alter table public.vineyards enable row level security;

drop policy if exists "vineyards_select_owner"   on public.vineyards;
drop policy if exists "vineyards_select_member"  on public.vineyards;
drop policy if exists "vineyards_insert_owner"   on public.vineyards;
drop policy if exists "vineyards_update_owner"   on public.vineyards;
drop policy if exists "vineyards_delete_owner"   on public.vineyards;

-- Any member (including owner via membership row or owner_id) can read
create policy "vineyards_select_member"
    on public.vineyards
    for select
    to authenticated
    using ( public.is_vineyard_member(vineyards.id::text) );

-- Only owner can create / update / delete the vineyard record itself
create policy "vineyards_insert_owner"
    on public.vineyards
    for insert
    to authenticated
    with check ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) );

create policy "vineyards_update_owner"
    on public.vineyards
    for update
    to authenticated
    using  ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) )
    with check ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) );

create policy "vineyards_delete_owner"
    on public.vineyards
    for delete
    to authenticated
    using ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) );

-- =====================================================================
-- vineyard_members
-- =====================================================================
alter table public.vineyard_members enable row level security;

drop policy if exists "vineyard_members_select_self"         on public.vineyard_members;
drop policy if exists "vineyard_members_select_same_vineyard" on public.vineyard_members;
drop policy if exists "vineyard_members_insert_self"         on public.vineyard_members;
drop policy if exists "vineyard_members_insert_manager"      on public.vineyard_members;
drop policy if exists "vineyard_members_update_manager"      on public.vineyard_members;
drop policy if exists "vineyard_members_delete_manager"      on public.vineyard_members;

-- Everyone in a vineyard can see the full member list for that vineyard
create policy "vineyard_members_select_same_vineyard"
    on public.vineyard_members
    for select
    to authenticated
    using ( public.is_vineyard_member(vineyard_members.vineyard_id::text) );

-- A user can insert their OWN membership row (used by accept-invite
-- fallback). The RPC uses SECURITY DEFINER so it bypasses this anyway.
create policy "vineyard_members_insert_self"
    on public.vineyard_members
    for insert
    to authenticated
    with check ( lower(vineyard_members.user_id::text) = lower(auth.uid()::text) );

-- Owners / managers can update member rows in their vineyard
create policy "vineyard_members_update_manager"
    on public.vineyard_members
    for update
    to authenticated
    using (
        exists (
            select 1 from public.vineyards v
             where v.id::text = vineyard_members.vineyard_id::text
               and lower(v.owner_id::text) = lower(auth.uid()::text)
        )
        or exists (
            select 1 from public.vineyard_members vm
             where vm.vineyard_id::text = vineyard_members.vineyard_id::text
               and lower(vm.user_id::text) = lower(auth.uid()::text)
               and vm.role in ('Owner','Manager')
        )
    )
    with check (
        exists (
            select 1 from public.vineyards v
             where v.id::text = vineyard_members.vineyard_id::text
               and lower(v.owner_id::text) = lower(auth.uid()::text)
        )
        or exists (
            select 1 from public.vineyard_members vm
             where vm.vineyard_id::text = vineyard_members.vineyard_id::text
               and lower(vm.user_id::text) = lower(auth.uid()::text)
               and vm.role in ('Owner','Manager')
        )
    );

-- Owners / managers can remove members; a user can remove themselves
create policy "vineyard_members_delete_manager"
    on public.vineyard_members
    for delete
    to authenticated
    using (
        lower(vineyard_members.user_id::text) = lower(auth.uid()::text)
        or exists (
            select 1 from public.vineyards v
             where v.id::text = vineyard_members.vineyard_id::text
               and lower(v.owner_id::text) = lower(auth.uid()::text)
        )
        or exists (
            select 1 from public.vineyard_members vm
             where vm.vineyard_id::text = vineyard_members.vineyard_id::text
               and lower(vm.user_id::text) = lower(auth.uid()::text)
               and vm.role in ('Owner','Manager')
        )
    );

-- =====================================================================
-- vineyard_data
-- =====================================================================
alter table public.vineyard_data enable row level security;

drop policy if exists "vineyard_data_select_owner"   on public.vineyard_data;
drop policy if exists "vineyard_data_select_member"  on public.vineyard_data;
drop policy if exists "vineyard_data_insert_owner"   on public.vineyard_data;
drop policy if exists "vineyard_data_insert_member"  on public.vineyard_data;
drop policy if exists "vineyard_data_update_owner"   on public.vineyard_data;
drop policy if exists "vineyard_data_update_member"  on public.vineyard_data;
drop policy if exists "vineyard_data_delete_owner"   on public.vineyard_data;
drop policy if exists "vineyard_data_delete_member"  on public.vineyard_data;

create policy "vineyard_data_select_member"
    on public.vineyard_data
    for select
    to authenticated
    using ( public.is_vineyard_member(vineyard_data.vineyard_id::text) );

create policy "vineyard_data_insert_member"
    on public.vineyard_data
    for insert
    to authenticated
    with check ( public.is_vineyard_member(vineyard_data.vineyard_id::text) );

create policy "vineyard_data_update_member"
    on public.vineyard_data
    for update
    to authenticated
    using  ( public.is_vineyard_member(vineyard_data.vineyard_id::text) )
    with check ( public.is_vineyard_member(vineyard_data.vineyard_id::text) );

create policy "vineyard_data_delete_member"
    on public.vineyard_data
    for delete
    to authenticated
    using ( public.is_vineyard_member(vineyard_data.vineyard_id::text) );

-- =====================================================================
-- Sanity check
-- =====================================================================
select 'vineyards rows'         as what, count(*) as n from public.vineyards
union all
select 'vineyard_members rows',       count(*)        from public.vineyard_members
union all
select 'vineyard_data rows',          count(*)        from public.vineyard_data
union all
select 'distinct vineyards with >1 member',
       count(*) from (
           select vineyard_id from public.vineyard_members
           group by vineyard_id having count(*) > 1
       ) s;
