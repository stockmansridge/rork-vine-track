-- =====================================================================
-- Fix: "permission denied for table users" on invitations
--
-- Cause: Legacy RLS policies on public.invitations reference auth.users
-- directly (SELECT email FROM auth.users ...). The `authenticated` role
-- does not have SELECT on auth.users, so as soon as Postgres evaluates
-- those policies it errors out — even if another permissive policy
-- would have granted access.
--
-- Fix: drop the legacy policies. The newer policies
-- (invitations_select_invitee_or_manager, etc.) use auth.jwt() ->> 'email'
-- which does not touch auth.users and works for the authenticated role.
--
-- HOW TO APPLY:
--   1. Open Supabase Dashboard -> SQL Editor
--   2. Paste this ENTIRE file
--   3. Click "Run"
-- =====================================================================

drop policy if exists "Users can view their invitations"   on public.invitations;
drop policy if exists "Users can update their invitations" on public.invitations;
drop policy if exists "Members can insert invitations"     on public.invitations;

-- Sanity check: list remaining policies
select policyname, cmd
from pg_policies
where schemaname = 'public' and tablename = 'invitations'
order by policyname;

-- =====================================================================
-- Diagnostic: verify the current user is authorised for their vineyard.
-- Replace <VINEYARD_ID> with the vineyard you're testing.
-- Expected: at least one row with is_owner = true OR is_member = true.
-- =====================================================================
-- select
--   auth.uid()::text                                   as my_uid,
--   (auth.jwt() ->> 'email')                           as my_email,
--   (select v.owner_id from public.vineyards v
--     where v.id::text = '<VINEYARD_ID>')              as vineyard_owner_id,
--   exists (select 1 from public.vineyards v
--     where v.id::text = '<VINEYARD_ID>'
--       and v.owner_id::text = auth.uid()::text)       as is_owner,
--   exists (select 1 from public.vineyard_members vm
--     where vm.vineyard_id::text = '<VINEYARD_ID>'
--       and vm.user_id::text = auth.uid()::text)       as is_member;
