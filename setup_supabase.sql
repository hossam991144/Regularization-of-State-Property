-- HOSSAM GIS Request Tracking: run this entire script in Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.request_datasets (
  dataset_id uuid not null,
  request_id text not null,
  applicant_name text not null default '',
  center text not null default '',
  village text not null default '',
  completed_file text,
  primary key (dataset_id, request_id)
);

create table if not exists public.app_settings (
  id integer primary key check (id = 1),
  active_dataset_id uuid,
  master_name text not null default '',
  sub_names jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

insert into public.app_settings (id) values (1)
on conflict (id) do nothing;

alter table public.request_datasets enable row level security;
alter table public.app_settings enable row level security;

grant select on public.request_datasets to anon, authenticated;
grant insert, update, delete on public.request_datasets to authenticated;
grant select on public.app_settings to anon, authenticated;
grant update on public.app_settings to authenticated;

 drop policy if exists "Public can read request datasets" on public.request_datasets;
create policy "Public can read request datasets" on public.request_datasets
for select to anon, authenticated using (true);

drop policy if exists "Admins manage request datasets" on public.request_datasets;
create policy "Admins manage request datasets" on public.request_datasets
for all to authenticated
using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Public can read app settings" on public.app_settings;
create policy "Public can read app settings" on public.app_settings
for select to anon, authenticated using (true);

drop policy if exists "Admins update app settings" on public.app_settings;
create policy "Admins update app settings" on public.app_settings
for update to authenticated
using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create or replace function public.activate_request_dataset(
  p_dataset_id uuid,
  p_master_name text,
  p_sub_names jsonb default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'admin' then
    raise exception 'Admin access required';
  end if;
  if not exists (select 1 from public.request_datasets where dataset_id = p_dataset_id) then
    raise exception 'Dataset is empty or does not exist';
  end if;
  update public.app_settings
     set active_dataset_id = p_dataset_id,
         master_name = coalesce(p_master_name, ''),
         sub_names = coalesce(p_sub_names, '[]'::jsonb),
         updated_at = now()
   where id = 1;
  delete from public.request_datasets where dataset_id <> p_dataset_id;
end;
$$;

create or replace function public.mark_requests_completed(
  p_dataset_id uuid,
  p_request_ids text[],
  p_file_name text
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare affected integer;
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'admin' then
    raise exception 'Admin access required';
  end if;
  update public.request_datasets
     set completed_file = p_file_name
   where dataset_id = p_dataset_id
     and request_id = any(coalesce(p_request_ids, array[]::text[]))
     and completed_file is null;
  get diagnostics affected = row_count;
  return affected;
end;
$$;

revoke all on function public.activate_request_dataset(uuid, text, jsonb) from public;
revoke all on function public.mark_requests_completed(uuid, text[], text) from public;
grant execute on function public.activate_request_dataset(uuid, text, jsonb) to authenticated;
grant execute on function public.mark_requests_completed(uuid, text[], text) to authenticated;
