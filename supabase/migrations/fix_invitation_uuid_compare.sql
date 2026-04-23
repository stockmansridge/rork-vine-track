-- Fix create_invitation: compare IDs as uuid (case-insensitive) instead of text
create or replace function public.create_invitation(
    p_vineyard_id text,
    p_vineyard_name text,
    p_email text,
    p_role text,
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
            where v.id::uuid = p_vineyard_id::uuid
              and lower(v.owner_id::text) = lower(v_uid)
        )
        or exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id::uuid = p_vineyard_id::uuid
              and lower(vm.user_id::text) = lower(v_uid)
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

grant execute on function public.create_invitation(text, text, text, text, text) to authenticated;
