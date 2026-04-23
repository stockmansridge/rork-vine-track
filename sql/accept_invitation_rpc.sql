-- =====================================================================
-- accept_invitation RPC — SECURITY DEFINER bypass to reliably add the
-- current authenticated user to vineyard_members when they accept an
-- invitation.
--
-- WHY THIS EXISTS:
--   The RLS insert policy on vineyard_members compares
--     auth.uid()::text = user_id
--   which uses a LOWERCASE uuid string. The iOS client was inserting the
--   user_id as an UPPERCASE uuid (UUID.uuidString), so every accept
--   silently failed with a policy violation — no error surfaced to the
--   UI, and invited users never appeared in vineyard_members.
--
--   This RPC sidesteps the whole issue: it runs as definer, inserts the
--   row with the CANONICAL lowercase uid from auth.uid(), and flips the
--   invitation to accepted atomically.
--
-- HOW TO APPLY:
--   1. Open Supabase Dashboard -> SQL Editor
--   2. Paste this ENTIRE file
--   3. Click "Run"
-- =====================================================================

-- ---------- Fix any rows that were inserted with uppercase user_id ----
update public.vineyard_members
   set user_id = lower(user_id)
 where user_id <> lower(user_id);

-- ---------- Cancel orphaned invitations whose vineyard was deleted ----
-- Prevents FK violations in the backfill + RPC below.
update public.invitations
   set status = 'cancelled'
 where status = 'pending'
   and not exists (
       select 1 from public.vineyards v
        where v.id::text = invitations.vineyard_id::text
   );

-- ---------- Ensure (vineyard_id, user_id) is unique so upsert works ---
-- (No-op if the constraint already exists.)
do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'vineyard_members_vineyard_user_unique'
    ) then
        begin
            alter table public.vineyard_members
                add constraint vineyard_members_vineyard_user_unique
                unique (vineyard_id, user_id);
        exception when duplicate_table or unique_violation then
            -- dupes exist; dedupe first
            delete from public.vineyard_members a
             using public.vineyard_members b
             where a.ctid < b.ctid
               and a.vineyard_id::text = b.vineyard_id::text
               and lower(a.user_id)    = lower(b.user_id);
            alter table public.vineyard_members
                add constraint vineyard_members_vineyard_user_unique
                unique (vineyard_id, user_id);
        end;
    end if;
end $$;

-- ---------- Drop previous versions ------------------------------------
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
    v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
    v_inv   public.invitations;
    v_name  text;
    v_row   public.vineyard_members;
begin
    if v_uid is null or v_uid = '' then
        raise exception 'Not authenticated';
    end if;

    select * into v_inv
      from public.invitations
     where id::text = p_invitation_id
     limit 1;

    if v_inv.id is null then
        raise exception 'Invitation not found: %', p_invitation_id;
    end if;

    if not exists (select 1 from public.vineyards v where v.id::text = v_inv.vineyard_id::text) then
        update public.invitations set status = 'cancelled' where id = v_inv.id;
        raise exception 'The vineyard for this invitation no longer exists';
    end if;

    if lower(v_inv.email) <> v_email then
        raise exception 'This invitation (%) is for % but you are signed in as %',
            p_invitation_id, v_inv.email, v_email;
    end if;

    -- Best-effort name: profile.name -> auth full_name -> email local part
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

    return v_row;
end;
$$;

alter function public.accept_invitation(text) owner to postgres;
revoke all on function public.accept_invitation(text) from public;
grant execute on function public.accept_invitation(text) to authenticated;

-- ---------- accept_pending_invitations_for_me() -----------------------
-- Auto-accepts ALL pending invitations addressed to the signed-in user's
-- email. Returns the number accepted. Called right after sign-in.
create or replace function public.accept_pending_invitations_for_me()
returns integer
language plpgsql
security definer
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
    if v_uid is null or v_uid = '' or v_email = '' then
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
           and exists (select 1 from public.vineyards v where v.id::text = i.vineyard_id::text)
    loop
        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        values (v_inv.vineyard_id, v_uid, coalesce(v_name, ''), v_inv.role)
        on conflict (vineyard_id, user_id)
        do update set role = excluded.role,
                      name = coalesce(nullif(excluded.name, ''), public.vineyard_members.name);

        update public.invitations
           set status = 'accepted'
         where id = v_inv.id;

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$$;

alter function public.accept_pending_invitations_for_me() owner to postgres;
revoke all on function public.accept_pending_invitations_for_me() from public;
grant execute on function public.accept_pending_invitations_for_me() to authenticated;

-- ---------- One-shot backfill: accept every pending invitation whose --
-- email matches an existing auth user. Safe to run repeatedly. --------
do $$
declare
    v_inv   record;
    v_uid   text;
    v_name  text;
begin
    for v_inv in
        select i.*
          from public.invitations i
         where i.status = 'pending'
           and exists (select 1 from public.vineyards v where v.id::text = i.vineyard_id::text)
    loop
        select lower(au.id::text) into v_uid
          from auth.users au
         where lower(au.email) = lower(v_inv.email)
         limit 1;

        if v_uid is null then
            continue;
        end if;

        select coalesce(
            (select p.name  from public.profiles p where p.id::text = v_uid),
            (select au.raw_user_meta_data ->> 'full_name' from auth.users au where au.id::text = v_uid),
            split_part(v_inv.email, '@', 1)
        ) into v_name;

        insert into public.vineyard_members (vineyard_id, user_id, name, role)
        values (v_inv.vineyard_id, v_uid, coalesce(v_name, ''), v_inv.role)
        on conflict (vineyard_id, user_id) do nothing;

        update public.invitations set status = 'accepted' where id = v_inv.id;
    end loop;
end $$;

-- ---------- Sanity ----------------------------------------------------
select 'vineyard_members rows' as what, count(*) as n from public.vineyard_members
union all
select 'pending invitations remaining', count(*) from public.invitations where status = 'pending'
union all
select 'accepted invitations', count(*) from public.invitations where status = 'accepted';
