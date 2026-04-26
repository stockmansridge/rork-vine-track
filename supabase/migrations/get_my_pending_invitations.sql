-- See sql/get_my_pending_invitations.sql for documentation.

create or replace function public.get_my_pending_invitations()
returns table(
    id uuid,
    vineyard_id text,
    vineyard_name text,
    email text,
    role text,
    invited_by text,
    invited_by_name text,
    status text,
    created_at text
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

    if current_email is null or current_email = '' then
        return;
    end if;

    return query
    select
        i.id,
        i.vineyard_id::text,
        i.vineyard_name,
        i.email,
        i.role,
        case when i.invited_by is null then null else i.invited_by::text end,
        i.invited_by_name,
        i.status,
        case when i.created_at is null then null else i.created_at::text end
      from public.invitations i
     where i.status = 'pending'
       and lower(trim(i.email)) = current_email
     order by i.created_at desc nulls last;
end;
$$;

grant execute on function public.get_my_pending_invitations() to authenticated;
