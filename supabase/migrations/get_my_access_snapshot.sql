-- Step 2: Single source of truth for access state.
--
-- get_my_access_snapshot() returns everything the app needs after
-- authentication so it can stop chaining multiple fallbacks:
--
--   - user            : currently authenticated user
--   - vineyards       : every vineyard the user can access
--   - memberships     : the user's role in each accessible vineyard
--   - pendingInvitations : invitations awaiting acceptance
--   - vineyardData    : per-vineyard data records (kept for parity with
--                        the previous snapshot RPC so the app can hydrate
--                        in one round-trip)
--
-- Access rules (a vineyard appears in `vineyards` only when ONE of these
-- is true):
--   1. the user has a vineyard_members row for it, OR
--   2. the user is the vineyard.owner_id, OR
--   3. an invitation that has been accepted produced a membership row
--
-- A pending invitation does NOT grant access. It is surfaced separately
-- in pendingInvitations so the UI can prompt the user to accept it.

create or replace function public.get_my_access_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
declare
    v_uid uuid := auth.uid();
    v_uid_text text := lower(coalesce(auth.uid()::text, ''));
    v_email text;
    v_name text;
    v_result jsonb;
begin
    if v_uid is null then
        return jsonb_build_object(
            'user', null,
            'vineyards', '[]'::jsonb,
            'memberships', '[]'::jsonb,
            'pendingInvitations', '[]'::jsonb,
            'vineyardData', '[]'::jsonb
        );
    end if;

    select lower(trim(coalesce(
        (select u.email from auth.users u where u.id = v_uid limit 1),
        (select p.email from public.profiles p where lower(p.id::text) = v_uid_text limit 1),
        auth.jwt() ->> 'email'
    ))) into v_email;

    if v_email = '' then
        v_email := null;
    end if;

    select coalesce(
        nullif(trim((select p.name from public.profiles p where lower(p.id::text) = v_uid_text limit 1)), ''),
        nullif(trim((select (u.raw_user_meta_data ->> 'full_name') from auth.users u where u.id = v_uid limit 1)), ''),
        v_email,
        ''
    ) into v_name;

    -- Heal missing membership rows when the user clearly should have
    -- access (owner of a vineyard, or an accepted invitation matched
    -- their email). This keeps the access path consistent regardless of
    -- which sign-in method the user came from.
    if v_email is not null then
        begin
            with candidate_roles as (
                select v.id as vineyard_id, 'Owner'::text as role
                  from public.vineyards v
                 where lower(v.owner_id::text) = v_uid_text
                union
                select v.id, 'Owner'::text
                  from public.vineyards v
                  join auth.users u on lower(u.id::text) = lower(v.owner_id::text)
                 where lower(trim(u.email)) = v_email
                union
                select i.vineyard_id, coalesce(i.role, 'Operator')
                  from public.invitations i
                 where lower(trim(coalesce(i.email, ''))) = v_email
                   and lower(coalesce(i.status, '')) = 'accepted'
                   and i.vineyard_id is not null
            )
            insert into public.vineyard_members (vineyard_id, user_id, name, role)
            select distinct cr.vineyard_id, v_uid, coalesce(v_name, v_email), cr.role
              from candidate_roles cr
             where cr.vineyard_id is not null
               and not exists (
                   select 1
                     from public.vineyard_members existing
                    where lower(existing.vineyard_id::text) = lower(cr.vineyard_id::text)
                      and lower(existing.user_id::text) = v_uid_text
               )
            on conflict (vineyard_id, user_id) do nothing;
        exception when others then
            raise notice 'get_my_access_snapshot membership repair skipped: %', sqlerrm;
        end;
    end if;

    with accessible_ids as (
        -- 1. owner_id matches the current user
        select v.id::text as vineyard_id
          from public.vineyards v
         where lower(v.owner_id::text) = v_uid_text
        union
        -- 2. explicit membership row exists for the current user
        select vm.vineyard_id::text
          from public.vineyard_members vm
         where lower(vm.user_id::text) = v_uid_text
    )
    select jsonb_build_object(
        'user', jsonb_build_object(
            'id', v_uid::text,
            'email', coalesce(v_email, ''),
            'name', coalesce(v_name, '')
        ),
        'vineyards', coalesce((
            select jsonb_agg(distinct jsonb_build_object(
                'id', v.id::text,
                'name', coalesce(v.name, ''),
                'owner_id', case when v.owner_id is null then null else v.owner_id::text end,
                'logo_data', v.logo_data,
                'created_at', case when v.created_at is null then null else v.created_at::text end,
                'country', coalesce(v.country, '')
            ))
              from public.vineyards v
              join accessible_ids a on lower(a.vineyard_id) = lower(v.id::text)
        ), '[]'::jsonb),
        'memberships', coalesce((
            select jsonb_agg(jsonb_build_object(
                'vineyard_id', vm.vineyard_id::text,
                'user_id', vm.user_id::text,
                'email', coalesce(au.email, p.email, case when vm.name like '%@%' then vm.name else null end),
                'display_name', coalesce(nullif(p.name, ''), nullif(vm.name, ''), au.email, p.email, ''),
                'role', coalesce(vm.role, 'Operator'),
                'joined_at', case when vm.joined_at is null then null else vm.joined_at::text end
            ))
              from public.vineyard_members vm
              join accessible_ids a on lower(a.vineyard_id) = lower(vm.vineyard_id::text)
              left join auth.users au on lower(au.id::text) = lower(vm.user_id::text)
              left join public.profiles p on lower(p.id::text) = lower(vm.user_id::text)
        ), '[]'::jsonb),
        'pendingInvitations', coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', i.id,
                'vineyard_id', i.vineyard_id::text,
                'vineyard_name', i.vineyard_name,
                'email', i.email,
                'role', coalesce(i.role, 'Operator'),
                'invited_by', case when i.invited_by is null then null else i.invited_by::text end,
                'invited_by_name', i.invited_by_name,
                'status', coalesce(i.status, 'pending'),
                'created_at', case when i.created_at is null then null else i.created_at::text end
            ) order by i.created_at desc nulls last)
              from public.invitations i
             where v_email is not null
               and lower(trim(coalesce(i.email, ''))) = v_email
               and lower(coalesce(i.status, '')) = 'pending'
        ), '[]'::jsonb),
        'vineyardData', coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', vd.id::text,
                'vineyard_id', vd.vineyard_id::text,
                'data_type', vd.data_type,
                'data', vd.data,
                'updated_at', case when vd.updated_at is null then null else vd.updated_at::text end
            ))
              from public.vineyard_data vd
              join accessible_ids a on lower(a.vineyard_id) = lower(vd.vineyard_id::text)
        ), '[]'::jsonb)
    )
    into v_result;

    return coalesce(v_result, jsonb_build_object(
        'user', null,
        'vineyards', '[]'::jsonb,
        'memberships', '[]'::jsonb,
        'pendingInvitations', '[]'::jsonb,
        'vineyardData', '[]'::jsonb
    ));
end;
$$;

alter function public.get_my_access_snapshot() owner to postgres;
revoke all on function public.get_my_access_snapshot() from public;
grant execute on function public.get_my_access_snapshot() to authenticated;
