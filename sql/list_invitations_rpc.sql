-- =====================================================================
-- list_invitations_for_vineyard RPC — SECURITY DEFINER read helper
-- Fixes: "invitations do not appear in the Invitations section of the
-- vineyard, even though the email was delivered".
--
-- The email goes out because the insert runs through the
-- create_invitation RPC (SECURITY DEFINER), but the subsequent SELECT
-- is subject to RLS. If the RLS SELECT policy was never applied (or
-- applied with a different column type) the query returns 0 rows.
--
-- This RPC authorises the caller in-body and returns the rows,
-- bypassing RLS — identical pattern to create_invitation.
--
-- HOW TO APPLY:
--   1. Open Supabase Dashboard -> SQL Editor
--   2. Paste this ENTIRE file
--   3. Click "Run"
-- =====================================================================

drop function if exists public.list_invitations_for_vineyard(uuid);
drop function if exists public.list_invitations_for_vineyard(text);

create or replace function public.list_invitations_for_vineyard(
    p_vineyard_id text
)
returns setof public.invitations
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid text := auth.uid()::text;
    v_authorized boolean;
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
              and vm.user_id::text     = v_uid
        )
    into v_authorized;

    if not v_authorized then
        raise exception 'You do not have permission to view invitations for this vineyard';
    end if;

    return query
        select *
        from public.invitations
        where vineyard_id::text = p_vineyard_id
        order by created_at desc nulls last;
end;
$$;

grant execute on function public.list_invitations_for_vineyard(text) to authenticated;
