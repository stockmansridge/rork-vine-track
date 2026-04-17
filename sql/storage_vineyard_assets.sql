-- Supabase Storage bucket for vineyard-scoped assets (custom EL stage images, etc.)
-- Run once in the Supabase SQL editor.

insert into storage.buckets (id, name, public)
values ('vineyard-assets', 'vineyard-assets', false)
on conflict (id) do nothing;

-- Only members of a vineyard can read/write objects under that vineyard's folder.
-- Path format: <vineyard_id>/<anything>

drop policy if exists "vineyard_assets_select" on storage.objects;
create policy "vineyard_assets_select"
on storage.objects for select
to authenticated
using (
  bucket_id = 'vineyard-assets'
  and exists (
    select 1 from public.vineyard_members m
    where m.vineyard_id::text = split_part(storage.objects.name, '/', 1)
      and m.user_id = auth.uid()::text
  )
);

drop policy if exists "vineyard_assets_insert" on storage.objects;
create policy "vineyard_assets_insert"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'vineyard-assets'
  and exists (
    select 1 from public.vineyard_members m
    where m.vineyard_id::text = split_part(storage.objects.name, '/', 1)
      and m.user_id = auth.uid()::text
  )
);

drop policy if exists "vineyard_assets_update" on storage.objects;
create policy "vineyard_assets_update"
on storage.objects for update
to authenticated
using (
  bucket_id = 'vineyard-assets'
  and exists (
    select 1 from public.vineyard_members m
    where m.vineyard_id::text = split_part(storage.objects.name, '/', 1)
      and m.user_id = auth.uid()::text
  )
);

drop policy if exists "vineyard_assets_delete" on storage.objects;
create policy "vineyard_assets_delete"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'vineyard-assets'
  and exists (
    select 1 from public.vineyard_members m
    where m.vineyard_id::text = split_part(storage.objects.name, '/', 1)
      and m.user_id = auth.uid()::text
  )
);
