-- get_my_vineyards_full.sql
--
-- Returns the FULL vineyard records (not just ids) the current signed-in
-- user should have access to, bypassing RLS via SECURITY DEFINER. This
-- removes the previous fragility where get_my_vineyard_ids returned ids
-- but the follow-up `from('vineyards').select().eq('id', vid)` was denied
-- by RLS on the new auth identity (e.g. fresh Google sign-in on a shared
-- device), leaving the user stuck on the "Welcome to VineTrack" screen.
--
-- Inclusion rules match get_my_vineyard_ids:
--   1. Vineyards owned by current uid.
--   2. Vineyards where current uid is a member.
--   3. Vineyards owned by ANY auth.users row sharing the same email.
--   4. Vineyards where ANY auth.users row sharing the same email is a
--      member.
--
-- Auto-heals vineyard_members so subsequent RLS-protected queries (like
-- vineyard_data) succeed for the new uid.

create or replace function public.get_my_vineyards_full()
returns table(
    id uuid,
    name text,
    owner_id uuid,
    logo_data text,
    created_at timestamptz,
    country text
)
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

    if current_email is not null and current_email <> '' then
        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        select v.id, current_uid, current_email, 'Owner'
          from public.vineyards v
          join auth.users u on lower(u.id::text) = lower(v.owner_id::text)
         where lower(u.email) = current_email
           and lower(v.owner_id::text) <> lower(current_uid::text)
        on conflict (vineyard_id, user_id) do nothing;

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
    select distinct
        v.id,
        v.name,
        v.owner_id,
        v.logo_data,
        v.created_at,
        coalesce(v.country, '') as country
      from public.vineyards v
      join ids on ids.vid = v.id;
end;
$$;

grant execute on function public.get_my_vineyards_full() to authenticated;
