-- claim_vineyards_by_email.sql
--
-- Adds the currently signed-in user as a member of any vineyards that are
-- owned by ANOTHER auth user sharing the same email address. This handles
-- the case where a user originally created their vineyard via email +
-- password and later signs in with Google (or Apple) on a new device, which
-- in Supabase creates a separate auth.users row with a different uuid.
--
-- It also adds them as a member of any vineyards where another auth user
-- with their email is already a member. This way invited users don't lose
-- access when they switch sign-in providers.
--
-- The function is SECURITY DEFINER so it can read auth.users and bypass RLS
-- on vineyard_members for the insert. It NEVER changes the vineyard
-- owner_id - it only grants access via membership.
--
-- Run this in the Supabase SQL editor.

create or replace function public.claim_vineyards_by_email()
returns table(vineyard_id uuid, role text)
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid := auth.uid();
    current_email text;
    v_rec record;
begin
    if current_uid is null then
        return;
    end if;

    select lower(email) into current_email
    from auth.users
    where id = current_uid;

    if current_email is null or current_email = '' then
        return;
    end if;

    -- 1) Vineyards OWNED by another auth user with the same email.
    --    Add the current user as an owner-level member so they regain
    --    access on the new device.
    for v_rec in
        select distinct v.id as vid, 'owner'::text as role_name
        from public.vineyards v
        join auth.users u on lower(u.id::text) = lower(v.owner_id::text)
        where lower(u.email) = current_email
          and lower(v.owner_id::text) <> lower(current_uid::text)
    loop
        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        values (v_rec.vid, lower(current_uid::text), current_email, v_rec.role_name)
        on conflict (vineyard_id, user_id) do nothing;

        vineyard_id := v_rec.vid;
        role := v_rec.role_name;
        return next;
    end loop;

    -- 2) Vineyards where another auth user with the same email is a member.
    --    Copy their role to the current user so invitations accepted under
    --    a different identity carry over.
    for v_rec in
        select distinct m.vineyard_id as vid, m.role as role_name
        from public.vineyard_members m
        join auth.users u on lower(u.id::text) = lower(m.user_id::text)
        where lower(u.email) = current_email
          and lower(u.id::text) <> lower(current_uid::text)
    loop
        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        values (v_rec.vid, lower(current_uid::text), current_email, v_rec.role_name)
        on conflict (vineyard_id, user_id) do nothing;

        vineyard_id := v_rec.vid;
        role := v_rec.role_name;
        return next;
    end loop;
end;
$$;

grant execute on function public.claim_vineyards_by_email() to authenticated;
