-- =====================================================================
-- Invitations RLS Migration
-- Fixes: "new row violates row-level security policy for table invitations"
-- Allows Owner/Manager of a vineyard to create invitations, invitees to
-- read their own pending invitations, and both sides to update/delete.
-- =====================================================================

alter table public.invitations enable row level security;

-- --- INSERT: Owner/Manager of the target vineyard --------------------
drop policy if exists "invitations_insert_manager" on public.invitations;
create policy "invitations_insert_manager"
    on public.invitations
    for insert
    with check (
        invited_by = auth.uid()::text
        and exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id = invitations.vineyard_id
              and vm.user_id = auth.uid()::text
              and vm.role in ('Owner', 'Manager')
        )
    );

-- --- SELECT: invitee (by email) or a Manager/Owner of the vineyard --
drop policy if exists "invitations_select_invitee_or_manager" on public.invitations;
create policy "invitations_select_invitee_or_manager"
    on public.invitations
    for select
    using (
        lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
        or exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id = invitations.vineyard_id
              and vm.user_id = auth.uid()::text
              and vm.role in ('Owner', 'Manager')
        )
    );

-- --- UPDATE: invitee (to accept/decline) or Manager/Owner -----------
drop policy if exists "invitations_update_invitee_or_manager" on public.invitations;
create policy "invitations_update_invitee_or_manager"
    on public.invitations
    for update
    using (
        lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
        or exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id = invitations.vineyard_id
              and vm.user_id = auth.uid()::text
              and vm.role in ('Owner', 'Manager')
        )
    );

-- --- DELETE: Manager/Owner of the vineyard --------------------------
drop policy if exists "invitations_delete_manager" on public.invitations;
create policy "invitations_delete_manager"
    on public.invitations
    for delete
    using (
        exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id = invitations.vineyard_id
              and vm.user_id = auth.uid()::text
              and vm.role in ('Owner', 'Manager')
        )
    );
