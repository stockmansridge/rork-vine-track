-- =====================================================================
-- Diagnose a specific invited user by email.
--
-- HOW TO USE:
--   1. Replace '<EMAIL_HERE>' with the email of the invited user.
--   2. Run in the Supabase SQL Editor.
--   3. Read the numbered sections below top-to-bottom.
-- =====================================================================

-- ---------------- 0. the email we are inspecting --------------------
-- Supabase SQL Editor does not support psql meta-commands like \set.
-- Replace <EMAIL_HERE> in each VALUES(...) clause below, then run.

-- ---------------- 1. Does the user exist in auth.users? --------------
with target(email) as (values (lower('<EMAIL_HERE>')))
select '1. auth.users match' as step,
       au.id::text as uid,
       au.email,
       au.email_confirmed_at,
       au.last_sign_in_at
from auth.users au, target t
where lower(au.email) = t.email;

-- ---------------- 2. All invitations ever created for this email -----
with target(email) as (values (lower('<EMAIL_HERE>')))
select '2. invitations' as step,
       i.id::text         as invitation_id,
       i.vineyard_id::text,
       i.vineyard_name,
       i.email,
       i.role,
       i.status,
       i.invited_by::text,
       i.created_at,
       exists (
           select 1 from public.vineyards v
           where v.id::text = i.vineyard_id::text
       ) as vineyard_still_exists
from public.invitations i, target t
where lower(i.email) = t.email
order by i.created_at desc;

-- ---------------- 3. Do those vineyards still exist? -----------------
with target(email) as (values (lower('<EMAIL_HERE>')))
select '3. vineyards for those invitations' as step,
       v.id::text,
       v.name,
       v.owner_id::text
from public.vineyards v
where v.id::text in (
    select i.vineyard_id::text
    from public.invitations i, target t
    where lower(i.email) = t.email
);

-- ---------------- 4. Is the user already a member anywhere? ----------
with target(email) as (values (lower('<EMAIL_HERE>')))
select '4. vineyard_members for this user' as step,
       vm.vineyard_id::text,
       vm.user_id,
       vm.role,
       vm.joined_at
from public.vineyard_members vm
join auth.users au on au.id::text = vm.user_id::text,
     target t
where lower(au.email) = t.email;

-- ---------------- 5. Summary by status --------------------------------
with target(email) as (values (lower('<EMAIL_HERE>')))
select '5. invitation status counts' as step,
       coalesce(i.status, 'none') as status,
       count(*) as n
from target t
left join public.invitations i on lower(i.email) = t.email
group by i.status
order by status;

-- ---------------- 6. Does the RPC think they are a member? -----------
-- Run this separately while LOGGED IN as the invited user (use the
-- Supabase SQL Editor "Run as" drop-down). If the Run-as selector is
-- missing, skip this — sections 1–5 already show the answer.
-- select public.accept_pending_invitations_for_me() as accepted_now;
