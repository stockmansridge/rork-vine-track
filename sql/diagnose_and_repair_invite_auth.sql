-- =====================================================================
-- Diagnose + repair "Not authorised to invite" errors.
--
-- Run this ENTIRE file in Supabase SQL Editor while signed in as the
-- affected user's OWNER account (i.e. the person who created the
-- vineyards). It will:
--
--   1. Show which of your vineyards are mis-configured.
--   2. Back-fill vineyards.owner_id from vineyard_members where missing
--      or mismatched.
--   3. Insert a vineyard_members row with role='Owner' wherever the
--      vineyard's owner is not already in vineyard_members.
--   4. Make the create_invitation RPC more lenient so owning either via
--      vineyards.owner_id OR vineyard_members.role='Owner' works.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Diagnostic snapshot BEFORE repair
-- ---------------------------------------------------------------------
select 'BEFORE' as phase,
       v.id            as vineyard_id,
       v.name,
       v.owner_id,
       (select count(*) from public.vineyard_members vm
         where vm.vineyard_id = v.id)                       as member_count,
       (select string_agg(vm.user_id::text || ':' || vm.role, ', ')
          from public.vineyard_members vm
         where vm.vineyard_id = v.id)                       as members
  from public.vineyards v
 order by v.created_at;

-- ---------------------------------------------------------------------
-- 2. Back-fill vineyards.owner_id from an Owner member row if missing
-- ---------------------------------------------------------------------
update public.vineyards v
   set owner_id = vm.user_id
  from public.vineyard_members vm
 where vm.vineyard_id = v.id
   and vm.role = 'Owner'
   and (v.owner_id is null
        or lower(v.owner_id::text) <> lower(vm.user_id::text));

-- ---------------------------------------------------------------------
-- 3. Insert an Owner member row for any vineyard whose owner isn't in
--    vineyard_members yet.
-- ---------------------------------------------------------------------
insert into public.vineyard_members (vineyard_id, user_id, name, role)
select v.id,
       v.owner_id,
       coalesce((select p.name from public.profiles p where p.id = v.owner_id), ''),
       'Owner'
  from public.vineyards v
 where v.owner_id is not null
   and not exists (
         select 1 from public.vineyard_members vm
          where vm.vineyard_id = v.id
            and lower(vm.user_id::text) = lower(v.owner_id::text)
       )
on conflict (vineyard_id, user_id) do update
   set role = 'Owner'
 where public.vineyard_members.role not in ('Owner', 'Manager');

-- ---------------------------------------------------------------------
-- 4. Recreate create_invitation with a more tolerant authorization check
-- ---------------------------------------------------------------------
drop function if exists public.create_invitation(text, text, text, text, text);

create or replace function public.create_invitation(
    p_vineyard_id     text,
    p_vineyard_name   text,
    p_email           text,
    p_role            text,
    p_invited_by_name text
)
returns public.invitations
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    v_uid text := lower(auth.uid()::text);
    v_row public.invitations;
    v_is_owner   boolean;
    v_is_manager boolean;
begin
    if v_uid is null or v_uid = '' then
        raise exception 'Not authenticated';
    end if;

    select exists (
        select 1 from public.vineyards v
         where v.id::text = p_vineyard_id
           and lower(v.owner_id::text) = v_uid
    ) into v_is_owner;

    select exists (
        select 1 from public.vineyard_members vm
         where vm.vineyard_id::text = p_vineyard_id
           and lower(vm.user_id::text) = v_uid
           and vm.role in ('Owner','Manager')
    ) into v_is_manager;

    if not (v_is_owner or v_is_manager) then
        raise exception 'Not authorised to invite (uid=%, vineyard=%, owner=%, manager=%)',
            v_uid, p_vineyard_id, v_is_owner, v_is_manager;
    end if;

    insert into public.invitations
        (vineyard_id, vineyard_name, email, role, invited_by, invited_by_name, status)
    values
        (p_vineyard_id::uuid, p_vineyard_name, lower(p_email),
         p_role, v_uid::uuid, p_invited_by_name, 'pending')
    returning * into v_row;

    return v_row;
end;
$$;

alter function public.create_invitation(text, text, text, text, text) owner to postgres;
revoke all on function public.create_invitation(text, text, text, text, text) from public;
grant execute on function public.create_invitation(text, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Diagnostic snapshot AFTER repair
-- ---------------------------------------------------------------------
select 'AFTER' as phase,
       v.id            as vineyard_id,
       v.name,
       v.owner_id,
       (select count(*) from public.vineyard_members vm
         where vm.vineyard_id = v.id)                       as member_count,
       (select string_agg(vm.user_id::text || ':' || vm.role, ', ')
          from public.vineyard_members vm
         where vm.vineyard_id = v.id)                       as members
  from public.vineyards v
 order by v.created_at;
