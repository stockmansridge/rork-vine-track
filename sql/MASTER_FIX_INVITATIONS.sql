-- =====================================================================
-- MASTER FIX — run this ONE file in the Supabase SQL Editor.
--
-- This replaces every previous invitation / member fix. It is idempotent
-- and safe to re-run. Applies:
--
--   1. Unique constraint on (vineyard_id, user_id) so upserts work.
--   2. Normalises any existing uppercase user_id rows.
--   3. is_vineyard_member() helper (SECURITY DEFINER).
--   4. RLS policies on vineyards / vineyard_members / vineyard_data so
--      invited users can actually SEE the vineyard they joined.
--   5. RLS policies on invitations (invitee by email OR owner/manager).
--   6. create_invitation / accept_invitation / accept_pending_invitations_for_me
--      RPCs — all SECURITY DEFINER, all compare uuids safely.
--   7. Backfills every owner into vineyard_members and auto-accepts every
--      still-pending invitation whose email matches a real auth user.
--
-- HOW TO APPLY:
--   1. Supabase Dashboard -> SQL Editor -> New query
--   2. Paste this ENTIRE file
--   3. Click "Run"
--   4. Check the final SELECT at the bottom for sanity numbers.
-- =====================================================================

-- --------------------------------------------------------------------
-- 1. vineyard_members hygiene
-- --------------------------------------------------------------------
update public.vineyard_members
   set user_id = lower(user_id)
 where user_id <> lower(user_id);

-- Dedupe (vineyard_id, lower(user_id))
delete from public.vineyard_members a
 using public.vineyard_members b
 where a.ctid < b.ctid
   and a.vineyard_id::text = b.vineyard_id::text
   and lower(a.user_id)    = lower(b.user_id);

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'vineyard_members_vineyard_user_unique'
    ) then
        alter table public.vineyard_members
            add constraint vineyard_members_vineyard_user_unique
            unique (vineyard_id, user_id);
    end if;
end $$;

-- --------------------------------------------------------------------
-- 2. is_vineyard_member helper
-- --------------------------------------------------------------------
create or replace function public.is_vineyard_member(p_vineyard_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1 from public.vineyard_members vm
         where vm.vineyard_id::text = p_vineyard_id
           and lower(vm.user_id::text) = lower(auth.uid()::text)
    )
    or exists (
        select 1 from public.vineyards v
         where v.id::text = p_vineyard_id
           and lower(v.owner_id::text) = lower(auth.uid()::text)
    );
$$;

grant execute on function public.is_vineyard_member(text) to authenticated;

-- --------------------------------------------------------------------
-- 3. vineyards RLS
-- --------------------------------------------------------------------
alter table public.vineyards enable row level security;

drop policy if exists "vineyards_select_owner"   on public.vineyards;
drop policy if exists "vineyards_select_member"  on public.vineyards;
drop policy if exists "vineyards_insert_owner"   on public.vineyards;
drop policy if exists "vineyards_update_owner"   on public.vineyards;
drop policy if exists "vineyards_delete_owner"   on public.vineyards;

create policy "vineyards_select_member"
    on public.vineyards for select to authenticated
    using ( public.is_vineyard_member(vineyards.id::text) );

create policy "vineyards_insert_owner"
    on public.vineyards for insert to authenticated
    with check ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) );

create policy "vineyards_update_owner"
    on public.vineyards for update to authenticated
    using  ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) )
    with check ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) );

create policy "vineyards_delete_owner"
    on public.vineyards for delete to authenticated
    using ( lower(vineyards.owner_id::text) = lower(auth.uid()::text) );

-- --------------------------------------------------------------------
-- 4. vineyard_members RLS
-- --------------------------------------------------------------------
alter table public.vineyard_members enable row level security;

drop policy if exists "vineyard_members_select_self"         on public.vineyard_members;
drop policy if exists "vineyard_members_select_same_vineyard" on public.vineyard_members;
drop policy if exists "vineyard_members_insert_self"         on public.vineyard_members;
drop policy if exists "vineyard_members_insert_manager"      on public.vineyard_members;
drop policy if exists "vineyard_members_update_manager"      on public.vineyard_members;
drop policy if exists "vineyard_members_delete_manager"      on public.vineyard_members;

create policy "vineyard_members_select_same_vineyard"
    on public.vineyard_members for select to authenticated
    using ( public.is_vineyard_member(vineyard_members.vineyard_id::text) );

create policy "vineyard_members_insert_self"
    on public.vineyard_members for insert to authenticated
    with check ( lower(vineyard_members.user_id::text) = lower(auth.uid()::text) );

create policy "vineyard_members_update_manager"
    on public.vineyard_members for update to authenticated
    using (
        exists ( select 1 from public.vineyards v
                  where v.id::text = vineyard_members.vineyard_id::text
                    and lower(v.owner_id::text) = lower(auth.uid()::text) )
        or exists ( select 1 from public.vineyard_members vm
                     where vm.vineyard_id::text = vineyard_members.vineyard_id::text
                       and lower(vm.user_id::text) = lower(auth.uid()::text)
                       and vm.role in ('Owner','Manager') )
    )
    with check (
        exists ( select 1 from public.vineyards v
                  where v.id::text = vineyard_members.vineyard_id::text
                    and lower(v.owner_id::text) = lower(auth.uid()::text) )
        or exists ( select 1 from public.vineyard_members vm
                     where vm.vineyard_id::text = vineyard_members.vineyard_id::text
                       and lower(vm.user_id::text) = lower(auth.uid()::text)
                       and vm.role in ('Owner','Manager') )
    );

create policy "vineyard_members_delete_manager"
    on public.vineyard_members for delete to authenticated
    using (
        lower(vineyard_members.user_id::text) = lower(auth.uid()::text)
        or exists ( select 1 from public.vineyards v
                     where v.id::text = vineyard_members.vineyard_id::text
                       and lower(v.owner_id::text) = lower(auth.uid()::text) )
        or exists ( select 1 from public.vineyard_members vm
                     where vm.vineyard_id::text = vineyard_members.vineyard_id::text
                       and lower(vm.user_id::text) = lower(auth.uid()::text)
                       and vm.role in ('Owner','Manager') )
    );

-- --------------------------------------------------------------------
-- 5. vineyard_data RLS
-- --------------------------------------------------------------------
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
    on public.vineyard_data for select to authenticated
    using ( public.is_vineyard_member(vineyard_data.vineyard_id::text) );

create policy "vineyard_data_insert_member"
    on public.vineyard_data for insert to authenticated
    with check ( public.is_vineyard_member(vineyard_data.vineyard_id::text) );

create policy "vineyard_data_update_member"
    on public.vineyard_data for update to authenticated
    using  ( public.is_vineyard_member(vineyard_data.vineyard_id::text) )
    with check ( public.is_vineyard_member(vineyard_data.vineyard_id::text) );

create policy "vineyard_data_delete_member"
    on public.vineyard_data for delete to authenticated
    using ( public.is_vineyard_member(vineyard_data.vineyard_id::text) );

-- --------------------------------------------------------------------
-- 6. invitations RLS
-- --------------------------------------------------------------------
alter table public.invitations enable row level security;

drop policy if exists "invitations_insert_manager"            on public.invitations;
drop policy if exists "invitations_select_invitee_or_manager" on public.invitations;
drop policy if exists "invitations_update_invitee_or_manager" on public.invitations;
drop policy if exists "invitations_delete_manager"            on public.invitations;

create policy "invitations_insert_manager"
    on public.invitations for insert to authenticated
    with check (
        lower(invitations.invited_by::text) = lower(auth.uid()::text)
        and (
            exists ( select 1 from public.vineyards v
                      where v.id::text = invitations.vineyard_id::text
                        and lower(v.owner_id::text) = lower(auth.uid()::text) )
            or exists ( select 1 from public.vineyard_members vm
                         where vm.vineyard_id::text = invitations.vineyard_id::text
                           and lower(vm.user_id::text) = lower(auth.uid()::text)
                           and vm.role in ('Owner','Manager') )
        )
    );

create policy "invitations_select_invitee_or_manager"
    on public.invitations for select to authenticated
    using (
        lower(invitations.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
        or exists ( select 1 from public.vineyards v
                     where v.id::text = invitations.vineyard_id::text
                       and lower(v.owner_id::text) = lower(auth.uid()::text) )
        or exists ( select 1 from public.vineyard_members vm
                     where vm.vineyard_id::text = invitations.vineyard_id::text
                       and lower(vm.user_id::text) = lower(auth.uid()::text)
                       and vm.role in ('Owner','Manager') )
    );

create policy "invitations_update_invitee_or_manager"
    on public.invitations for update to authenticated
    using (
        lower(invitations.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
        or exists ( select 1 from public.vineyards v
                     where v.id::text = invitations.vineyard_id::text
                       and lower(v.owner_id::text) = lower(auth.uid()::text) )
    )
    with check (
        lower(invitations.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
        or exists ( select 1 from public.vineyards v
                     where v.id::text = invitations.vineyard_id::text
                       and lower(v.owner_id::text) = lower(auth.uid()::text) )
    );

create policy "invitations_delete_manager"
    on public.invitations for delete to authenticated
    using (
        exists ( select 1 from public.vineyards v
                  where v.id::text = invitations.vineyard_id::text
                    and lower(v.owner_id::text) = lower(auth.uid()::text) )
    );

-- --------------------------------------------------------------------
-- 7. RPCs (drop first so we can change return types safely)
-- --------------------------------------------------------------------
drop function if exists public.create_invitation(text, text, text, text, text);
drop function if exists public.accept_invitation(uuid);
drop function if exists public.accept_invitation(text);
drop function if exists public.accept_pending_invitations_for_me();
drop function if exists public.list_invitations_for_vineyard(text);

-- create_invitation
create or replace function public.create_invitation(
    p_vineyard_id text,
    p_vineyard_name text,
    p_email text,
    p_role text,
    p_invited_by_name text
)
returns public.invitations
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
    v_uid text := lower(auth.uid()::text);
    v_row public.invitations;
begin
    if v_uid is null or v_uid = '' then
        raise exception 'Not authenticated';
    end if;

    if not exists (
        select 1 from public.vineyards v
         where v.id::text = p_vineyard_id
           and lower(v.owner_id::text) = v_uid
    ) and not exists (
        select 1 from public.vineyard_members vm
         where vm.vineyard_id::text = p_vineyard_id
           and lower(vm.user_id::text) = v_uid
           and vm.role in ('Owner','Manager')
    ) then
        raise exception 'Not authorised to invite (uid=%, vineyard=%)', v_uid, p_vineyard_id;
    end if;

    insert into public.invitations
        (vineyard_id, vineyard_name, email, role, invited_by, invited_by_name, status)
    values
        (p_vineyard_id::uuid, p_vineyard_name, lower(p_email), p_role, v_uid::uuid, p_invited_by_name, 'pending')
    returning * into v_row;

    return v_row;
end;
$$;
grant execute on function public.create_invitation(text,text,text,text,text) to authenticated;

-- accept_invitation(p_invitation_id)
create or replace function public.accept_invitation(p_invitation_id text)
returns public.vineyard_members
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
    v_uid   text := lower(auth.uid()::text);
    v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
    v_inv   public.invitations;
    v_name  text;
    v_row   public.vineyard_members;
begin
    if v_uid is null or v_uid = '' then
        raise exception 'Not authenticated';
    end if;

    select * into v_inv from public.invitations
     where id::text = p_invitation_id limit 1;
    if v_inv.id is null then
        raise exception 'Invitation % not found', p_invitation_id;
    end if;

    if not exists (select 1 from public.vineyards v where v.id::text = v_inv.vineyard_id::text) then
        update public.invitations set status = 'cancelled' where id = v_inv.id;
        raise exception 'Vineyard no longer exists';
    end if;

    if lower(v_inv.email) <> v_email then
        raise exception 'Invitation is for % but you are signed in as %', v_inv.email, v_email;
    end if;

    select coalesce(
        (select p.name from public.profiles p where p.id::text = v_uid),
        (select au.raw_user_meta_data ->> 'full_name' from auth.users au where au.id::text = v_uid),
        split_part(v_email, '@', 1)
    ) into v_name;

    insert into public.vineyard_members (vineyard_id, user_id, name, role)
    values (v_inv.vineyard_id, v_uid, coalesce(v_name, ''), v_inv.role)
    on conflict (vineyard_id, user_id)
    do update set role = excluded.role,
                  name = coalesce(nullif(excluded.name, ''), public.vineyard_members.name)
    returning * into v_row;

    update public.invitations set status = 'accepted' where id = v_inv.id;
    return v_row;
end;
$$;
grant execute on function public.accept_invitation(text) to authenticated;

-- accept_pending_invitations_for_me
create or replace function public.accept_pending_invitations_for_me()
returns integer
language plpgsql security definer
set search_path = public
set row_security = off
as $$
declare
    v_uid   text := lower(auth.uid()::text);
    v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
    v_count integer := 0;
    v_inv   public.invitations;
    v_name  text;
begin
    -- Fallback: if JWT has no email claim, look it up by uid.
    if v_email = '' and v_uid <> '' then
        select lower(au.email) into v_email from auth.users au where au.id::text = v_uid limit 1;
    end if;

    if v_uid = '' or v_email is null or v_email = '' then
        return 0;
    end if;

    select coalesce(
        (select p.name from public.profiles p where p.id::text = v_uid),
        (select au.raw_user_meta_data ->> 'full_name' from auth.users au where au.id::text = v_uid),
        split_part(v_email, '@', 1)
    ) into v_name;

    for v_inv in
        select i.* from public.invitations i
         where lower(i.email) = v_email
           and i.status = 'pending'
           and exists (select 1 from public.vineyards v where v.id::text = i.vineyard_id::text)
    loop
        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        values (v_inv.vineyard_id, v_uid, coalesce(v_name, ''), v_inv.role)
        on conflict (vineyard_id, user_id)
        do update set role = excluded.role,
                      name = coalesce(nullif(excluded.name, ''), public.vineyard_members.name);

        update public.invitations set status = 'accepted' where id = v_inv.id;
        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$$;
grant execute on function public.accept_pending_invitations_for_me() to authenticated;

-- list_invitations_for_vineyard
create or replace function public.list_invitations_for_vineyard(p_vineyard_id text)
returns setof public.invitations
language sql security definer
set search_path = public
stable
as $$
    select * from public.invitations
     where vineyard_id::text = p_vineyard_id
     order by created_at desc;
$$;
grant execute on function public.list_invitations_for_vineyard(text) to authenticated;

-- --------------------------------------------------------------------
-- 8. Backfills
-- --------------------------------------------------------------------
-- Every owner must be a member of their own vineyard.
insert into public.vineyard_members (vineyard_id, user_id, name, role)
select v.id, lower(v.owner_id::text),
       coalesce((select p.name from public.profiles p where p.id::text = lower(v.owner_id::text)), 'Owner'),
       'Owner'
from public.vineyards v
where v.owner_id is not null
  and not exists (
      select 1 from public.vineyard_members vm
       where vm.vineyard_id::text = v.id::text
         and lower(vm.user_id::text) = lower(v.owner_id::text)
  )
on conflict (vineyard_id, user_id) do nothing;

-- Cancel invitations whose vineyard was deleted.
update public.invitations
   set status = 'cancelled'
 where status = 'pending'
   and not exists (
       select 1 from public.vineyards v where v.id::text = invitations.vineyard_id::text
   );

-- Auto-accept every still-pending invitation whose email matches a real user.
do $$
declare
    v_inv  record;
    v_uid  text;
    v_name text;
begin
    for v_inv in
        select i.* from public.invitations i
         where i.status = 'pending'
           and exists (select 1 from public.vineyards v where v.id::text = i.vineyard_id::text)
    loop
        select lower(au.id::text) into v_uid
          from auth.users au where lower(au.email) = lower(v_inv.email) limit 1;
        if v_uid is null then continue; end if;

        select coalesce(
            (select p.name from public.profiles p where p.id::text = v_uid),
            (select au.raw_user_meta_data ->> 'full_name' from auth.users au where au.id::text = v_uid),
            split_part(v_inv.email, '@', 1)
        ) into v_name;

        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        values (v_inv.vineyard_id, v_uid, coalesce(v_name, ''), v_inv.role)
        on conflict (vineyard_id, user_id) do nothing;

        update public.invitations set status = 'accepted' where id = v_inv.id;
    end loop;
end $$;

-- --------------------------------------------------------------------
-- 9. Sanity
-- --------------------------------------------------------------------
select 'vineyards'                                          as what, count(*) as n from public.vineyards
union all select 'vineyard_members',                         count(*) from public.vineyard_members
union all select 'vineyards with >1 member',
    count(*) from (
        select vineyard_id from public.vineyard_members
        group by vineyard_id having count(*) > 1
    ) s
union all select 'invitations pending',                      count(*) from public.invitations where status='pending'
union all select 'invitations accepted',                     count(*) from public.invitations where status='accepted'
union all select 'invitations cancelled',                    count(*) from public.invitations where status='cancelled';
