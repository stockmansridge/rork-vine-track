-- =====================================================================
-- Diagnostic: why can't we see invitations for a vineyard?
-- Run this in the Supabase SQL Editor WHILE LOGGED IN as the same user
-- that is viewing the vineyard in the app (use the "Run as" user selector
-- at the top of the SQL editor if available, otherwise it's fine -- we
-- will rely on the auth context).
-- =====================================================================

-- 1. Who does the DB think I am?
select auth.uid() as my_uid, auth.jwt() ->> 'email' as my_email;

-- 2. What column types do vineyards / invitations use?
select table_name, column_name, data_type
from information_schema.columns
where table_name in ('vineyards','invitations','vineyard_members')
  and column_name in ('id','owner_id','vineyard_id','user_id','invited_by','email');

-- 3. Show vineyards I own and my membership rows
select id, owner_id, name from public.vineyards;
select * from public.vineyard_members where user_id::text = auth.uid()::text;

-- 4. List invitations regardless of RLS (shows if rows exist at all)
select id, vineyard_id, email, status, invited_by, created_at
from public.invitations
order by created_at desc
limit 20;

-- 5. Show every RLS policy currently attached to invitations
select policyname, cmd, qual, with_check
from pg_policies
where schemaname='public' and tablename='invitations';
