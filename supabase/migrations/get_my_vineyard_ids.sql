-- get_my_vineyard_ids.sql
--
-- Returns every vineyard id the current signed-in user should have access
-- to, regardless of which auth identity created the records. This is the
-- server-side source of truth used by the app on every login so the
-- "Welcome / Create vineyard" screen never appears for a user who is
-- already an owner or member somewhere - even when they signed in via
-- a different provider (Google vs email/password) on a new/shared device.
--
-- Inclusion rules:
--   1. Vineyards where vineyards.owner_id = current auth uid.
--   2. Vineyards where the current user has a row in vineyard_members.
--   3. Vineyards owned by ANY auth.users row sharing the same email
--      (case-insensitive) as the current user.
--   4. Vineyards where ANY auth.users row sharing the same email is a
--      member - covers invitations accepted under a previous identity.
--
-- It also AUTO-HEALS access by inserting a vineyard_members row for the
-- current uid for every vineyard returned via rules 3/4, so subsequent
-- queries (vineyard_data, vineyards SELECT under RLS) succeed without
-- relying on a separate claim step.
--
-- Run this in the Supabase SQL editor.

create or replace function public.get_my_vineyard_ids()
returns table(vineyard_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid := auth.uid();
    current_email text;
begin
    if current_uid is null then
        return;
    end if;

    select lower(email) into current_email
    from auth.users
    where id = current_uid;

    -- Auto-heal: ensure the current uid has a vineyard_members row for
    -- every vineyard it should have access to via email match. Idempotent.
    if current_email is not null and current_email <> '' then
        -- Owner-by-email
        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        select v.id, current_uid, current_email, 'Owner'
          from public.vineyards v
          join auth.users u on lower(u.id::text) = lower(v.owner_id::text)
         where lower(u.email) = current_email
           and lower(v.owner_id::text) <> lower(current_uid::text)
        on conflict (vineyard_id, user_id) do nothing;

        -- Member-by-email (copy role)
        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        select distinct m.vineyard_id, current_uid, current_email, m.role
          from public.vineyard_members m
          join auth.users u on lower(u.id::text) = lower(m.user_id::text)
         where lower(u.email) = current_email
           and lower(u.id::text) <> lower(current_uid::text)
        on conflict (vineyard_id, user_id) do nothing;
    end if;

    return query
    with ids as (
        select v.id as vid
          from public.vineyards v
         where lower(v.owner_id::text) = lower(current_uid::text)
        union
        select m.vineyard_id
          from public.vineyard_members m
         where lower(m.user_id::text) = lower(current_uid::text)
        union
        select v.id
          from public.vineyards v
          join auth.users u on lower(u.id::text) = lower(v.owner_id::text)
         where current_email is not null
           and lower(u.email) = current_email
        union
        select m.vineyard_id
          from public.vineyard_members m
          join auth.users u on lower(u.id::text) = lower(m.user_id::text)
         where current_email is not null
           and lower(u.email) = current_email
    )
    select distinct vid from ids where vid is not null;
end;
$$;

grant execute on function public.get_my_vineyard_ids() to authenticated;
