-- =====================================================================
-- fix_accept_invitation_no_token_column.sql
--
-- Fixes: "column i.token does not exist"
--
-- The previous accept_invitation() in FINAL_FIX_INVITE_CASE.sql referenced
-- i.token, but the invitations table in this project has no `token`
-- column. This rebuilds the RPC to match on invitation id only (the app
-- already sends the invitation UUID as p_token).
--
-- Also hardens the insert into vineyard_members: if the parent vineyard
-- row is missing (orphaned invitation), we raise a clear error instead
-- of a generic FK violation.
--
-- Idempotent. Safe to re-run.
-- =====================================================================

-- Drop every overload so the signature is unambiguous
do $$
declare r record;
begin
    for r in
        select p.oid::regprocedure as sig
          from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('accept_invitation',
                             'accept_pending_invitations_for_me')
    loop
        execute 'drop function ' || r.sig::text || ' cascade';
    end loop;
end$$;

-- ---------------------------------------------------------------------
-- accept_invitation(p_token) — p_token is the invitation UUID as text
-- ---------------------------------------------------------------------
create or replace function public.accept_invitation(p_token text)
returns public.invitations
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid       uuid := auth.uid();
    v_email     text;
    v_inv       public.invitations;
    v_vineyard  public.vineyards;
    v_token_txt text := lower(btrim(coalesce(p_token, '')));
begin
    if v_uid is null then
        raise exception 'Not authenticated';
    end if;
    if v_token_txt = '' then
        raise exception 'Invitation id is required';
    end if;

    select lower(coalesce(au.email, ''))
      into v_email
      from auth.users au
     where lower(au.id::text) = lower(v_uid::text)
     limit 1;

    -- Match by invitation id (case-insensitive), scoped to this user's email
    select * into v_inv
      from public.invitations i
     where lower(i.id::text) = v_token_txt
       and i.status in ('pending','sent')
       and lower(i.email) = coalesce(v_email, '')
     limit 1;

    if v_inv.id is null then
        -- Retry without the email filter so we can tell the user precisely
        -- which check failed (expired vs. wrong account).
        select * into v_inv
          from public.invitations i
         where lower(i.id::text) = v_token_txt
         limit 1;

        if v_inv.id is null then
            raise exception 'Invitation not found';
        elsif v_inv.status not in ('pending','sent') then
            raise exception 'Invitation already %', v_inv.status;
        else
            raise exception 'Invitation is for a different email address';
        end if;
    end if;

    -- Confirm the parent vineyard actually exists before inserting,
    -- otherwise the FK error surfaces as a confusing 23503.
    select * into v_vineyard
      from public.vineyards v
     where lower(v.id::text) = lower(v_inv.vineyard_id::text)
     limit 1;

    if v_vineyard.id is null then
        raise exception 'The vineyard for this invitation no longer exists. Ask the owner to resend.';
    end if;

    insert into public.vineyard_members (vineyard_id, user_id, name, role)
    values (v_vineyard.id, v_uid,
            coalesce((select p.name from public.profiles p
                       where lower(p.id::text) = lower(v_uid::text)), ''),
            v_inv.role)
    on conflict (vineyard_id, user_id) do update
       set role = excluded.role;

    update public.invitations
       set status      = 'accepted',
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
-- accept_pending_invitations_for_me — same fix, no token column
-- ---------------------------------------------------------------------
create or replace function public.accept_pending_invitations_for_me()
returns setof public.invitations
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid   uuid := auth.uid();
    v_email text;
    v_inv   public.invitations;
begin
    if v_uid is null then
        return;
    end if;

    select lower(coalesce(au.email, ''))
      into v_email
      from auth.users au
     where lower(au.id::text) = lower(v_uid::text)
     limit 1;

    if v_email is null or v_email = '' then
        return;
    end if;

    for v_inv in
        select *
          from public.invitations i
         where i.status in ('pending','sent')
           and lower(i.email) = v_email
           and exists (
               select 1 from public.vineyards v
                where lower(v.id::text) = lower(i.vineyard_id::text)
           )
    loop
        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        values (v_inv.vineyard_id, v_uid,
                coalesce((select p.name from public.profiles p
                           where lower(p.id::text) = lower(v_uid::text)), ''),
                v_inv.role)
        on conflict (vineyard_id, user_id) do update
           set role = excluded.role;

        update public.invitations
           set status      = 'accepted',
               accepted_at = now(),
               accepted_by = v_uid
         where id = v_inv.id
         returning * into v_inv;

        return next v_inv;
    end loop;

    return;
end;
$$;

alter function public.accept_pending_invitations_for_me() owner to postgres;
revoke all on function public.accept_pending_invitations_for_me() from public;
grant execute on function public.accept_pending_invitations_for_me() to authenticated;
