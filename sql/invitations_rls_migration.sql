-- =====================================================================
-- Invitations RLS Migration (robust to text/uuid column types)
-- Fixes: "new row violates row-level security policy for table invitations"
--
-- HOW TO APPLY:
--   1. Open Supabase Dashboard -> SQL Editor
--   2. Paste this ENTIRE file
--   3. Click "Run"
-- =====================================================================

alter table public.invitations enable row level security;

-- Drop any previous versions of these policies
drop policy if exists "invitations_insert_manager"           on public.invitations;
drop policy if exists "invitations_select_invitee_or_manager" on public.invitations;
drop policy if exists "invitations_update_invitee_or_manager" on public.invitations;
drop policy if exists "invitations_delete_manager"            on public.invitations;
drop policy if exists "invitations_insert_self"               on public.invitations;
drop policy if exists "invitations_select_self"               on public.invitations;

-- --- INSERT: Owner of the vineyard (via vineyards.owner_id)
--            OR Owner/Manager in vineyard_members ---------------------
create policy "invitations_insert_manager"
    on public.invitations
    for insert
    to authenticated
    with check (
        invitations.invited_by::text = auth.uid()::text
        and (
            exists (
                select 1 from public.vineyards v
                where v.id::text       = invitations.vineyard_id::text
                  and v.owner_id::text = auth.uid()::text
            )
            or exists (
                select 1 from public.vineyard_members vm
                where vm.vineyard_id::text = invitations.vineyard_id::text
                  and vm.user_id::text    = auth.uid()::text
                  and vm.role in ('Owner', 'Manager')
            )
        )
    );

-- --- SELECT: invitee (by email) OR vineyard owner OR Owner/Manager ---
create policy "invitations_select_invitee_or_manager"
    on public.invitations
    for select
    to authenticated
    using (
        lower(invitations.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
        or exists (
            select 1 from public.vineyards v
            where v.id::text       = invitations.vineyard_id::text
              and v.owner_id::text = auth.uid()::text
        )
        or exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id::text = invitations.vineyard_id::text
              and vm.user_id::text    = auth.uid()::text
              and vm.role in ('Owner', 'Manager')
        )
    );

-- --- UPDATE: invitee (to accept/decline) OR vineyard owner OR manager --
create policy "invitations_update_invitee_or_manager"
    on public.invitations
    for update
    to authenticated
    using (
        lower(invitations.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
        or exists (
            select 1 from public.vineyards v
            where v.id::text       = invitations.vineyard_id::text
              and v.owner_id::text = auth.uid()::text
        )
        or exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id::text = invitations.vineyard_id::text
              and vm.user_id::text    = auth.uid()::text
              and vm.role in ('Owner', 'Manager')
        )
    )
    with check (
        lower(invitations.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
        or exists (
            select 1 from public.vineyards v
            where v.id::text       = invitations.vineyard_id::text
              and v.owner_id::text = auth.uid()::text
        )
        or exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id::text = invitations.vineyard_id::text
              and vm.user_id::text    = auth.uid()::text
              and vm.role in ('Owner', 'Manager')
        )
    );

-- --- DELETE: vineyard owner OR Owner/Manager ------------------------
create policy "invitations_delete_manager"
    on public.invitations
    for delete
    to authenticated
    using (
        exists (
            select 1 from public.vineyards v
            where v.id::text       = invitations.vineyard_id::text
              and v.owner_id::text = auth.uid()::text
        )
        or exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id::text = invitations.vineyard_id::text
              and vm.user_id::text    = auth.uid()::text
              and vm.role in ('Owner', 'Manager')
        )
    );

-- =====================================================================
-- BACKFILL: ensure every vineyard has its owner in vineyard_members
-- This handles vineyards created before the membership sync existed.
-- =====================================================================
insert into public.vineyard_members (vineyard_id, user_id, name, role)
select v.id, v.owner_id,
       coalesce((select p.email from public.profiles p where p.id::text = v.owner_id::text), 'Owner'),
       'Owner'
from public.vineyards v
where not exists (
    select 1 from public.vineyard_members vm
    where vm.vineyard_id::text = v.id::text
      and vm.user_id::text    = v.owner_id::text
)
on conflict do nothing;
