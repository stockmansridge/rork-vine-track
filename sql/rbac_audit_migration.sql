-- =====================================================================
-- RBAC + Audit Log Migration
-- Adds: audit_logs table + RLS helpers to enforce role-based deletes &
-- financial exports server-side.
-- =====================================================================

-- --- Audit Log Table ------------------------------------------------

create table if not exists public.audit_logs (
    id            uuid primary key default gen_random_uuid(),
    vineyard_id   text not null references public.vineyards(id) on delete cascade,
    user_id       uuid references auth.users(id) on delete set null,
    user_name     text not null default '',
    user_role     text not null default '',
    action        text not null,
    entity_type   text not null,
    entity_id     text,
    entity_label  text not null default '',
    details       text not null default '',
    created_at    timestamptz not null default now()
);

create index if not exists audit_logs_vineyard_created_idx
    on public.audit_logs (vineyard_id, created_at desc);

create index if not exists audit_logs_user_idx
    on public.audit_logs (user_id);

alter table public.audit_logs enable row level security;

-- --- Role Helper ----------------------------------------------------

create or replace function public.current_role_for_vineyard(vid text)
returns text
language sql
security definer
stable
as $$
    select role
    from public.vineyard_members
    where vineyard_id = vid
      and user_id = auth.uid()::text
    limit 1
$$;

-- --- Audit Log Policies --------------------------------------------

drop policy if exists "audit_logs_select_member" on public.audit_logs;
create policy "audit_logs_select_member"
    on public.audit_logs
    for select
    using (
        exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id = audit_logs.vineyard_id
              and vm.user_id = auth.uid()::text
              and vm.role in ('Owner', 'Manager')
        )
    );

drop policy if exists "audit_logs_insert_member" on public.audit_logs;
create policy "audit_logs_insert_member"
    on public.audit_logs
    for insert
    with check (
        exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id = audit_logs.vineyard_id
              and vm.user_id = auth.uid()::text
        )
    );

-- Audit logs are append-only; no updates or deletes from clients.
drop policy if exists "audit_logs_no_update" on public.audit_logs;
create policy "audit_logs_no_update"
    on public.audit_logs
    for update
    using (false);

drop policy if exists "audit_logs_no_delete" on public.audit_logs;
create policy "audit_logs_no_delete"
    on public.audit_logs
    for delete
    using (false);

-- --- Vineyard Data Delete Guard ------------------------------------
-- Operators are blocked from deleting vineyard_data rows. Supervisors
-- and above can delete. Hiding UI buttons is not enough; this enforces
-- it at the database layer.

drop policy if exists "vineyard_data_delete_supervisor_plus" on public.vineyard_data;
create policy "vineyard_data_delete_supervisor_plus"
    on public.vineyard_data
    for delete
    using (
        exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id = vineyard_data.vineyard_id
              and vm.user_id = auth.uid()::text
              and vm.role in ('Owner', 'Manager', 'Supervisor')
        )
    );

-- --- Vineyard Members: Manager-only writes -------------------------
-- Only Managers/Owners can add, remove, or change members.

drop policy if exists "vineyard_members_insert_manager" on public.vineyard_members;
create policy "vineyard_members_insert_manager"
    on public.vineyard_members
    for insert
    with check (
        -- First member being added (owner inserting themselves) is allowed,
        -- otherwise require Manager/Owner role on the vineyard.
        auth.uid()::text = user_id
        or exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id = vineyard_members.vineyard_id
              and vm.user_id = auth.uid()::text
              and vm.role in ('Owner', 'Manager')
        )
    );

drop policy if exists "vineyard_members_update_manager" on public.vineyard_members;
create policy "vineyard_members_update_manager"
    on public.vineyard_members
    for update
    using (
        exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id = vineyard_members.vineyard_id
              and vm.user_id = auth.uid()::text
              and vm.role in ('Owner', 'Manager')
        )
    );

drop policy if exists "vineyard_members_delete_manager" on public.vineyard_members;
create policy "vineyard_members_delete_manager"
    on public.vineyard_members
    for delete
    using (
        exists (
            select 1 from public.vineyard_members vm
            where vm.vineyard_id = vineyard_members.vineyard_id
              and vm.user_id = auth.uid()::text
              and vm.role in ('Owner', 'Manager')
        )
    );
