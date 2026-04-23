-- =====================================================================
-- create_invitation RPC — SECURITY DEFINER bypass for invitations RLS
-- Fixes: "new row violates row-level security policy for table invitations"
--
-- HOW TO APPLY:
--   1. Open Supabase Dashboard -> SQL Editor
--   2. Paste this ENTIRE file
--   3. Click "Run"
-- =====================================================================

-- Make sure owner is always in vineyard_members (one-time backfill)
insert into public.vineyard_members (vineyard_id, user_id, name, role)
select v.id, v.owner_id,
       coalesce((select p.email from public.profiles p where p.id::text = v.owner_id::text), 'Owner'),
       'Owner'
from public.vineyards v
where v.owner_id is not null
  and not exists (
    select 1 from public.vineyard_members vm
    where vm.vineyard_id::text = v.id::text
      and vm.user_id::text    = v.owner_id::text
  )
on conflict do nothing;

-- Drop any previous version
drop function if exists public.create_invitation(uuid, text, text, text, text);
drop function if exists public.create_invitation(text, text, text, text, text);

-- Runs with owner privileges, bypassing RLS, but enforces authorization in-body.
create or replace function public.create_invitation(
    p_vineyard_id   text,
    p_vineyard_name text,
    p_email         text,
    p_role          text,
    p_invited_by_name text
)
returns public.invitations
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid  text := auth.uid()::text;
    v_authorized boolean;
    v_row  public.invitations;
begin
    if v_uid is null then
        raise exception 'Not authenticated';
    end if;

    select
        exists (
            select 1 from public.vineyards v
            where v.id::text = p_vineyard_id
              and v.owner_id::text = v_uid
        )
        or exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id::text = p_vineyard_id
              and vm.user_id::text    = v_uid
              and vm.role in ('Owner', 'Manager')
        )
    into v_authorized;

    if not v_authorized then
        raise exception 'You do not have permission to invite members to this vineyard';
    end if;

    -- Insert; cast vineyard_id/invited_by to invitations' column types automatically.
    insert into public.invitations
        (vineyard_id, vineyard_name, email, role, invited_by, invited_by_name, status)
    values
        (p_vineyard_id, p_vineyard_name, lower(p_email), p_role, v_uid, p_invited_by_name, 'pending')
    returning * into v_row;

    return v_row;
end;
$$;

grant execute on function public.create_invitation(text, text, text, text, text) to authenticated;
