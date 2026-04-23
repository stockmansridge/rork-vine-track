-- =====================================================================
-- Fix: ensure create_invitation RPC bypasses RLS properly
--
-- The RPC was created as SECURITY DEFINER but if the function owner is
-- not the table owner (postgres), RLS still applies. This also re-grants
-- execute and makes the insert immune to RLS inside the function body.
--
-- HOW TO APPLY:
--   1. Open Supabase Dashboard -> SQL Editor
--   2. Paste this ENTIRE file
--   3. Click "Run"
-- =====================================================================

-- 1) Re-create the function with explicit row_security bypass inside body.
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
        raise exception 'You do not have permission to invite members to this vineyard (uid=%, vineyard=%)', v_uid, p_vineyard_id;
    end if;

    insert into public.invitations
        (vineyard_id, vineyard_name, email, role, invited_by, invited_by_name, status)
    values
        (p_vineyard_id, p_vineyard_name, lower(p_email), p_role, v_uid, p_invited_by_name, 'pending')
    returning * into v_row;

    return v_row;
end;
$$;

-- 2) Make sure the function is owned by postgres (table owner) so SECURITY
--    DEFINER actually bypasses RLS on public.invitations.
alter function public.create_invitation(text, text, text, text, text) owner to postgres;

-- 3) Grant execute to authenticated users only.
revoke all on function public.create_invitation(text, text, text, text, text) from public;
grant execute on function public.create_invitation(text, text, text, text, text) to authenticated;

-- 4) Sanity check - show owner after change.
select p.proname,
       pg_get_userbyid(p.proowner) as owner,
       p.prosecdef as security_definer
from pg_proc p
where p.proname = 'create_invitation';
