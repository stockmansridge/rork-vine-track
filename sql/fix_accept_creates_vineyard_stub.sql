-- =====================================================================
-- Fix: accept_invitation must not fail when the vineyard row is missing
-- from public.vineyards. Previously the RPC raised and cancelled the
-- invitation, or the fallback INSERT into vineyard_members hit a FK
-- violation ("vineyard_members_vineyard_id_fkey").
--
-- This version upserts a STUB vineyard row from the invitation's own
-- data (vineyard_id, vineyard_name, invited_by) so the membership FK
-- is always satisfied. Full vineyard data flows in via the normal
-- CloudSync pull afterwards.
--
-- HOW TO APPLY: paste this ENTIRE file into the Supabase SQL Editor
-- and click "Run". Idempotent - safe to run repeatedly.
-- =====================================================================

drop function if exists public.accept_invitation(uuid);
drop function if exists public.accept_invitation(text);
drop function if exists public.accept_pending_invitations_for_me();

-- ---------- accept_invitation(p_invitation_id) ------------------------
create or replace function public.accept_invitation(p_invitation_id text)
returns public.vineyard_members
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    v_uid   text := lower(auth.uid()::text);
    v_email text;
    v_inv   public.invitations;
    v_name  text;
    v_row   public.vineyard_members;
begin
    if v_uid is null or v_uid = '' then
        raise exception 'Not authenticated';
    end if;

    -- Resolve the signed-in user's email from auth.users (robust against
    -- missing JWT 'email' claim, OIDC, refreshed sessions, etc.).
    select lower(coalesce(au.email, ''))
      into v_email
      from auth.users au
     where lower(au.id::text) = v_uid
     limit 1;

    if v_email is null or v_email = '' then
        v_email := lower(coalesce(auth.jwt() ->> 'email', ''));
    end if;

    select * into v_inv
      from public.invitations
     where id::text = p_invitation_id
     limit 1;

    if v_inv.id is null then
        raise exception 'Invitation not found: %', p_invitation_id;
    end if;

    if v_email = '' or lower(v_inv.email) <> v_email then
        raise exception 'This invitation (%) is for % but you are signed in as %',
            p_invitation_id, v_inv.email, v_email;
    end if;

    -- If the vineyard row is missing, create a stub from the invitation
    -- so the vineyard_members FK is satisfied. The owner is the inviter.
    if not exists (select 1 from public.vineyards v where v.id = v_inv.vineyard_id) then
        insert into public.vineyards (id, name, owner_id, created_at)
        values (
            v_inv.vineyard_id,
            coalesce(nullif(v_inv.vineyard_name, ''), 'Vineyard'),
            v_inv.invited_by,
            now()
        )
        on conflict (id) do nothing;

        -- Also make sure the inviter has an Owner membership row.
        if v_inv.invited_by is not null then
            insert into public.vineyard_members (vineyard_id, user_id, name, role)
            values (v_inv.vineyard_id, v_inv.invited_by::text,
                    coalesce(v_inv.invited_by_name, ''), 'Owner')
            on conflict (vineyard_id, user_id) do nothing;
        end if;
    end if;

    select coalesce(
        (select p.name  from public.profiles p where p.id::text = v_uid),
        (select au.raw_user_meta_data ->> 'full_name' from auth.users au where au.id::text = v_uid),
        split_part(v_email, '@', 1)
    ) into v_name;

    insert into public.vineyard_members (vineyard_id, user_id, name, role)
    values (v_inv.vineyard_id, v_uid, coalesce(v_name, ''), v_inv.role)
    on conflict (vineyard_id, user_id)
    do update set role = excluded.role,
                  name = coalesce(nullif(excluded.name, ''), public.vineyard_members.name)
    returning * into v_row;

    update public.invitations
       set status = 'accepted'
     where id = v_inv.id;

    -- Cancel any other pending duplicates for same (vineyard, email).
    update public.invitations
       set status = 'cancelled'
     where vineyard_id = v_inv.vineyard_id
       and lower(email) = v_email
       and id <> v_inv.id
       and status = 'pending';

    return v_row;
end;
$$;

alter function public.accept_invitation(text) owner to postgres;
revoke all on function public.accept_invitation(text) from public;
grant execute on function public.accept_invitation(text) to authenticated;

-- ---------- accept_pending_invitations_for_me() -----------------------
create or replace function public.accept_pending_invitations_for_me()
returns integer
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    v_uid   text := lower(auth.uid()::text);
    v_email text;
    v_count integer := 0;
    v_inv   public.invitations;
    v_name  text;
begin
    if v_uid is null or v_uid = '' then
        return 0;
    end if;

    select lower(coalesce(au.email, ''))
      into v_email
      from auth.users au
     where lower(au.id::text) = v_uid
     limit 1;

    if v_email is null or v_email = '' then
        v_email := lower(coalesce(auth.jwt() ->> 'email', ''));
    end if;

    if v_email is null or v_email = '' then
        return 0;
    end if;

    select coalesce(
        (select p.name  from public.profiles p where p.id::text = v_uid),
        (select au.raw_user_meta_data ->> 'full_name' from auth.users au where au.id::text = v_uid),
        split_part(v_email, '@', 1)
    ) into v_name;

    for v_inv in
        select i.* from public.invitations i
         where lower(i.email) = v_email
           and i.status = 'pending'
    loop
        -- Stub vineyard if missing (same logic as single accept).
        if not exists (select 1 from public.vineyards v where v.id = v_inv.vineyard_id) then
            insert into public.vineyards (id, name, owner_id, created_at)
            values (
                v_inv.vineyard_id,
                coalesce(nullif(v_inv.vineyard_name, ''), 'Vineyard'),
                v_inv.invited_by,
                now()
            )
            on conflict (id) do nothing;

            if v_inv.invited_by is not null then
                insert into public.vineyard_members (vineyard_id, user_id, name, role)
                values (v_inv.vineyard_id, v_inv.invited_by::text,
                        coalesce(v_inv.invited_by_name, ''), 'Owner')
                on conflict (vineyard_id, user_id) do nothing;
            end if;
        end if;

        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        values (v_inv.vineyard_id, v_uid, coalesce(v_name, ''), v_inv.role)
        on conflict (vineyard_id, user_id)
        do update set role = excluded.role,
                      name = coalesce(nullif(excluded.name, ''), public.vineyard_members.name);

        update public.invitations
           set status = 'accepted'
         where id = v_inv.id;

        update public.invitations
           set status = 'cancelled'
         where vineyard_id = v_inv.vineyard_id
           and lower(email) = v_email
           and id <> v_inv.id
           and status = 'pending';

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$$;

alter function public.accept_pending_invitations_for_me() owner to postgres;
revoke all on function public.accept_pending_invitations_for_me() from public;
grant execute on function public.accept_pending_invitations_for_me() to authenticated;

-- ---------- Force PostgREST to reload its schema cache ---------------
notify pgrst, 'reload schema';

-- ---------- Sanity ----------------------------------------------------
select 'pending invitations'  as what, count(*) from public.invitations where status = 'pending'
union all
select 'accepted invitations',  count(*) from public.invitations where status = 'accepted'
union all
select 'cancelled invitations', count(*) from public.invitations where status = 'cancelled'
union all
select 'vineyards rows',        count(*) from public.vineyards
union all
select 'vineyard_members rows', count(*) from public.vineyard_members;
