-- =====================================================================
-- fix_members_with_email.sql
--
-- NEW STRATEGY: stop relying on RLS + profiles.name for the team list.
--
-- Problem history:
--   Invited users accept OK, the row lands in vineyard_members, but the
--   owner's "Team & Access" screen either shows nothing new, or shows
--   rows with an EMPTY name ("") because profiles.name is blank. Tapping
--   those empty rows looks exactly like the "Add User" screen, which is
--   why every previous fix appeared to change nothing.
--
-- This migration:
--   1. Backfills vineyard_members.name from auth.users.email whenever
--      name is blank.
--   2. Rebuilds accept_invitation so newly-accepted members always have
--      at least their email as a name.
--   3. Adds a SECURITY DEFINER RPC `get_vineyard_members_with_email`
--      that the iOS app calls directly. This bypasses any lingering
--      RLS / profiles quirks and always returns (user_id, email,
--      display_name, role) for every member of a vineyard, provided
--      the caller is themselves a member of that vineyard.
--
-- Idempotent. Safe to re-run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Backfill blank names with email from auth.users
-- ---------------------------------------------------------------------
update public.vineyard_members vm
   set name = au.email
  from auth.users au
 where lower(au.id::text) = lower(vm.user_id::text)
   and (vm.name is null or btrim(vm.name) = '');

-- ---------------------------------------------------------------------
-- 2. Rebuild accept_invitation so name never ends up blank
-- ---------------------------------------------------------------------
drop function if exists public.accept_invitation(text) cascade;

create or replace function public.accept_invitation(p_token text)
returns public.invitations
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid   uuid := auth.uid();
    v_email text;
    v_name  text;
    v_inv   public.invitations;
begin
    if v_uid is null then
        raise exception 'Not authenticated';
    end if;

    select lower(coalesce(au.email, ''))
      into v_email
      from auth.users au
     where lower(au.id::text) = lower(v_uid::text)
     limit 1;

    select coalesce(nullif(btrim(p.name), ''), v_email, '')
      into v_name
      from public.profiles p
     where lower(p.id::text) = lower(v_uid::text)
     limit 1;

    if v_name is null or btrim(v_name) = '' then
        v_name := coalesce(v_email, '');
    end if;

    select * into v_inv
      from public.invitations i
     where (lower(i.token) = lower(btrim(p_token))
            or lower(i.id::text) = lower(btrim(p_token)))
       and i.status in ('pending','sent')
       and lower(i.email) = coalesce(v_email,'')
     limit 1;

    if v_inv.id is null then
        raise exception 'Invitation not found for this account';
    end if;

    insert into public.vineyard_members (vineyard_id, user_id, name, role)
    values (v_inv.vineyard_id, v_uid, v_name, v_inv.role)
    on conflict (vineyard_id, user_id) do update
       set role = excluded.role,
           name = case
               when public.vineyard_members.name is null
                 or btrim(public.vineyard_members.name) = ''
               then excluded.name
               else public.vineyard_members.name
           end;

    update public.invitations
       set status = 'accepted',
           accepted_at = now(),
           accepted_by = v_uid
     where id = v_inv.id
     returning * into v_inv;

    return v_inv;
end;
$$;

alter function public.accept_invitation(text) owner to postgres;
revoke all on function public.accept_invitation(text) from public;
grant execute on function public.accept_invitation(text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. get_vineyard_members_with_email — the new, reliable read path
-- ---------------------------------------------------------------------
drop function if exists public.get_vineyard_members_with_email(text) cascade;

create or replace function public.get_vineyard_members_with_email(p_vineyard_id text)
returns table (
    user_id       text,
    email         text,
    display_name  text,
    role          text,
    joined_at     timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid_txt text := lower(coalesce(auth.uid()::text, ''));
    v_vid_txt text := lower(btrim(coalesce(p_vineyard_id, '')));
    v_allowed boolean := false;
begin
    if v_uid_txt = '' then
        raise exception 'Not authenticated';
    end if;

    select exists (
        select 1 from public.vineyards v
         where lower(v.id::text) = v_vid_txt
           and lower(v.owner_id::text) = v_uid_txt
    )
    or exists (
        select 1 from public.vineyard_members vm
         where lower(vm.vineyard_id::text) = v_vid_txt
           and lower(vm.user_id::text) = v_uid_txt
    ) into v_allowed;

    if not v_allowed then
        raise exception 'Not a member of this vineyard';
    end if;

    return query
        select  lower(vm.user_id::text)                             as user_id,
                coalesce(au.email, '')                              as email,
                coalesce(
                    nullif(btrim(vm.name), ''),
                    nullif(btrim(p.name), ''),
                    au.email,
                    ''
                )                                                   as display_name,
                vm.role                                             as role,
                vm.joined_at                                        as joined_at
          from public.vineyard_members vm
          left join auth.users au
                 on lower(au.id::text) = lower(vm.user_id::text)
          left join public.profiles p
                 on lower(p.id::text)  = lower(vm.user_id::text)
         where lower(vm.vineyard_id::text) = v_vid_txt
         order by vm.joined_at asc nulls last;
end;
$$;

alter function public.get_vineyard_members_with_email(text) owner to postgres;
revoke all on function public.get_vineyard_members_with_email(text) from public;
grant execute on function public.get_vineyard_members_with_email(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Sanity check
-- ---------------------------------------------------------------------
select 'members with blank names remaining' as what,
       count(*) as n
  from public.vineyard_members
 where name is null or btrim(name) = '';
