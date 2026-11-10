-- Inventra database for Supabase. Generated from lib/core/db/schema.dart.
-- Run once in Supabase → SQL Editor. Safe to re-run: uses IF NOT EXISTS / OR REPLACE.
--
-- Notes
-- * Dates are stored as ISO-8601 text, exactly as the app writes them, so
--   comparisons like sold_at >= '2026-11-09T00:00:00Z' work the same on the
--   phone and on the server.
-- * Money is bigint in minor units (kobo, cents, fen).
-- * Nothing is hard-deleted: rows get deleted_at, so deletes sync to every phone.

-- Helper: current time as the same ISO text the app uses.
create or replace function public.now_iso() returns text
language sql stable as $$
  select to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
$$;

create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text,
  owner_id text,
  default_currency text,
  report_currency text,
  phone text,
  address text,
  receipt_footer text,
  created_at text,
  updated_at text
);
alter table public.businesses add column if not exists name text;
alter table public.businesses add column if not exists owner_id text;
alter table public.businesses add column if not exists default_currency text;
alter table public.businesses add column if not exists report_currency text;
alter table public.businesses add column if not exists phone text;
alter table public.businesses add column if not exists address text;
alter table public.businesses add column if not exists receipt_footer text;
alter table public.businesses add column if not exists created_at text;
alter table public.businesses add column if not exists updated_at text;

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  created_at text,
  updated_at text,
  updated_by text,
  deleted_at text,
  user_id text,
  display_name text,
  role text,
  permissions text,
  shop_ids text
);
alter table public.members add column if not exists business_id uuid;
alter table public.members add column if not exists created_at text;
alter table public.members add column if not exists updated_at text;
alter table public.members add column if not exists updated_by text;
alter table public.members add column if not exists deleted_at text;
alter table public.members add column if not exists user_id text;
alter table public.members add column if not exists display_name text;
alter table public.members add column if not exists role text;
alter table public.members add column if not exists permissions text;
alter table public.members add column if not exists shop_ids text;
create index if not exists members_business_idx on public.members(business_id);

create table if not exists public.main_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  created_at text,
  updated_at text,
  updated_by text,
  deleted_at text,
  name text,
  currency text,
  is_temporary bigint,
  archived_at text
);
alter table public.main_categories add column if not exists business_id uuid;
alter table public.main_categories add column if not exists created_at text;
alter table public.main_categories add column if not exists updated_at text;
alter table public.main_categories add column if not exists updated_by text;
alter table public.main_categories add column if not exists deleted_at text;
alter table public.main_categories add column if not exists name text;
alter table public.main_categories add column if not exists currency text;
alter table public.main_categories add column if not exists is_temporary bigint;
alter table public.main_categories add column if not exists archived_at text;
create index if not exists main_categories_business_idx on public.main_categories(business_id);

create table if not exists public.item_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  created_at text,
  updated_at text,
  updated_by text,
  deleted_at text,
  main_category_id uuid,
  name text,
  is_temporary bigint,
  archived_at text
);
alter table public.item_categories add column if not exists business_id uuid;
alter table public.item_categories add column if not exists created_at text;
alter table public.item_categories add column if not exists updated_at text;
alter table public.item_categories add column if not exists updated_by text;
alter table public.item_categories add column if not exists deleted_at text;
alter table public.item_categories add column if not exists main_category_id uuid;
alter table public.item_categories add column if not exists name text;
alter table public.item_categories add column if not exists is_temporary bigint;
alter table public.item_categories add column if not exists archived_at text;
create index if not exists item_categories_business_idx on public.item_categories(business_id);
create index if not exists item_categories_shop_idx on public.item_categories(main_category_id);

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  created_at text,
  updated_at text,
  updated_by text,
  deleted_at text,
  main_category_id uuid,
  item_category_id uuid,
  name text,
  barcode text,
  description text,
  base_unit text,
  currency text,
  cost_price bigint,
  selling_price bigint,
  low_stock_level bigint,
  size text,
  discontinued bigint,
  expiry_date text,
  image_path text,
  note text
);
alter table public.items add column if not exists business_id uuid;
alter table public.items add column if not exists created_at text;
alter table public.items add column if not exists updated_at text;
alter table public.items add column if not exists updated_by text;
alter table public.items add column if not exists deleted_at text;
alter table public.items add column if not exists main_category_id uuid;
alter table public.items add column if not exists item_category_id uuid;
alter table public.items add column if not exists name text;
alter table public.items add column if not exists barcode text;
alter table public.items add column if not exists description text;
alter table public.items add column if not exists base_unit text;
alter table public.items add column if not exists currency text;
alter table public.items add column if not exists cost_price bigint;
alter table public.items add column if not exists selling_price bigint;
alter table public.items add column if not exists low_stock_level bigint;
alter table public.items add column if not exists size text;
alter table public.items add column if not exists discontinued bigint;
alter table public.items add column if not exists expiry_date text;
alter table public.items add column if not exists image_path text;
alter table public.items add column if not exists note text;
create index if not exists items_business_idx on public.items(business_id);
create index if not exists items_shop_idx on public.items(main_category_id);

create table if not exists public.item_units (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  created_at text,
  updated_at text,
  updated_by text,
  deleted_at text,
  item_id uuid,
  name text,
  barcode text,
  units_per_pack bigint,
  selling_price bigint
);
alter table public.item_units add column if not exists business_id uuid;
alter table public.item_units add column if not exists created_at text;
alter table public.item_units add column if not exists updated_at text;
alter table public.item_units add column if not exists updated_by text;
alter table public.item_units add column if not exists deleted_at text;
alter table public.item_units add column if not exists item_id uuid;
alter table public.item_units add column if not exists name text;
alter table public.item_units add column if not exists barcode text;
alter table public.item_units add column if not exists units_per_pack bigint;
alter table public.item_units add column if not exists selling_price bigint;
create index if not exists item_units_business_idx on public.item_units(business_id);

create table if not exists public.price_history (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  item_id uuid,
  unit_id uuid,
  price_type text,
  old_price bigint,
  new_price bigint,
  changed_at text,
  changed_by text
);
alter table public.price_history add column if not exists business_id uuid;
alter table public.price_history add column if not exists item_id uuid;
alter table public.price_history add column if not exists unit_id uuid;
alter table public.price_history add column if not exists price_type text;
alter table public.price_history add column if not exists old_price bigint;
alter table public.price_history add column if not exists new_price bigint;
alter table public.price_history add column if not exists changed_at text;
alter table public.price_history add column if not exists changed_by text;
create index if not exists price_history_business_idx on public.price_history(business_id);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  created_at text,
  updated_at text,
  updated_by text,
  deleted_at text,
  company_name text,
  contact_name text,
  phone text,
  email text,
  address text,
  note text
);
alter table public.suppliers add column if not exists business_id uuid;
alter table public.suppliers add column if not exists created_at text;
alter table public.suppliers add column if not exists updated_at text;
alter table public.suppliers add column if not exists updated_by text;
alter table public.suppliers add column if not exists deleted_at text;
alter table public.suppliers add column if not exists company_name text;
alter table public.suppliers add column if not exists contact_name text;
alter table public.suppliers add column if not exists phone text;
alter table public.suppliers add column if not exists email text;
alter table public.suppliers add column if not exists address text;
alter table public.suppliers add column if not exists note text;
create index if not exists suppliers_business_idx on public.suppliers(business_id);

create table if not exists public.item_suppliers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  created_at text,
  updated_at text,
  updated_by text,
  deleted_at text,
  item_id uuid,
  supplier_id uuid,
  supply_price bigint,
  currency text,
  last_supplied_at text
);
alter table public.item_suppliers add column if not exists business_id uuid;
alter table public.item_suppliers add column if not exists created_at text;
alter table public.item_suppliers add column if not exists updated_at text;
alter table public.item_suppliers add column if not exists updated_by text;
alter table public.item_suppliers add column if not exists deleted_at text;
alter table public.item_suppliers add column if not exists item_id uuid;
alter table public.item_suppliers add column if not exists supplier_id uuid;
alter table public.item_suppliers add column if not exists supply_price bigint;
alter table public.item_suppliers add column if not exists currency text;
alter table public.item_suppliers add column if not exists last_supplied_at text;
create index if not exists item_suppliers_business_idx on public.item_suppliers(business_id);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  created_at text,
  updated_at text,
  updated_by text,
  deleted_at text,
  name text,
  phone text,
  email text,
  address text,
  note text
);
alter table public.customers add column if not exists business_id uuid;
alter table public.customers add column if not exists created_at text;
alter table public.customers add column if not exists updated_at text;
alter table public.customers add column if not exists updated_by text;
alter table public.customers add column if not exists deleted_at text;
alter table public.customers add column if not exists name text;
alter table public.customers add column if not exists phone text;
alter table public.customers add column if not exists email text;
alter table public.customers add column if not exists address text;
alter table public.customers add column if not exists note text;
create index if not exists customers_business_idx on public.customers(business_id);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  created_at text,
  updated_at text,
  updated_by text,
  deleted_at text,
  receipt_no text,
  main_category_id uuid,
  customer_id uuid,
  currency text,
  subtotal bigint,
  discount bigint,
  total bigint,
  amount_paid bigint,
  payment_status text,
  sold_at text,
  sold_by text,
  voided_at text,
  note text
);
alter table public.sales add column if not exists business_id uuid;
alter table public.sales add column if not exists created_at text;
alter table public.sales add column if not exists updated_at text;
alter table public.sales add column if not exists updated_by text;
alter table public.sales add column if not exists deleted_at text;
alter table public.sales add column if not exists receipt_no text;
alter table public.sales add column if not exists main_category_id uuid;
alter table public.sales add column if not exists customer_id uuid;
alter table public.sales add column if not exists currency text;
alter table public.sales add column if not exists subtotal bigint;
alter table public.sales add column if not exists discount bigint;
alter table public.sales add column if not exists total bigint;
alter table public.sales add column if not exists amount_paid bigint;
alter table public.sales add column if not exists payment_status text;
alter table public.sales add column if not exists sold_at text;
alter table public.sales add column if not exists sold_by text;
alter table public.sales add column if not exists voided_at text;
alter table public.sales add column if not exists note text;
create index if not exists sales_business_idx on public.sales(business_id);
create index if not exists sales_shop_idx on public.sales(main_category_id);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  sale_id uuid,
  item_id uuid,
  item_name text,
  unit_id uuid,
  unit_name text,
  units_per_pack bigint,
  quantity bigint,
  base_quantity bigint,
  unit_price bigint,
  cost_price bigint,
  line_total bigint
);
alter table public.sale_items add column if not exists business_id uuid;
alter table public.sale_items add column if not exists sale_id uuid;
alter table public.sale_items add column if not exists item_id uuid;
alter table public.sale_items add column if not exists item_name text;
alter table public.sale_items add column if not exists unit_id uuid;
alter table public.sale_items add column if not exists unit_name text;
alter table public.sale_items add column if not exists units_per_pack bigint;
alter table public.sale_items add column if not exists quantity bigint;
alter table public.sale_items add column if not exists base_quantity bigint;
alter table public.sale_items add column if not exists unit_price bigint;
alter table public.sale_items add column if not exists cost_price bigint;
alter table public.sale_items add column if not exists line_total bigint;
create index if not exists sale_items_business_idx on public.sale_items(business_id);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  sale_id uuid,
  amount bigint,
  method text,
  paid_at text,
  received_by text
);
alter table public.payments add column if not exists business_id uuid;
alter table public.payments add column if not exists sale_id uuid;
alter table public.payments add column if not exists amount bigint;
alter table public.payments add column if not exists method text;
alter table public.payments add column if not exists paid_at text;
alter table public.payments add column if not exists received_by text;
create index if not exists payments_business_idx on public.payments(business_id);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  main_category_id uuid,
  item_id uuid,
  change bigint,
  reason text,
  ref_id uuid,
  note text,
  created_at text,
  created_by text
);
alter table public.stock_movements add column if not exists business_id uuid;
alter table public.stock_movements add column if not exists main_category_id uuid;
alter table public.stock_movements add column if not exists item_id uuid;
alter table public.stock_movements add column if not exists change bigint;
alter table public.stock_movements add column if not exists reason text;
alter table public.stock_movements add column if not exists ref_id uuid;
alter table public.stock_movements add column if not exists note text;
alter table public.stock_movements add column if not exists created_at text;
alter table public.stock_movements add column if not exists created_by text;
create index if not exists stock_movements_business_idx on public.stock_movements(business_id);
create index if not exists stock_movements_shop_idx on public.stock_movements(main_category_id);

create table if not exists public.restocks (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  created_at text,
  updated_at text,
  updated_by text,
  deleted_at text,
  main_category_id uuid,
  supplier_id uuid,
  item_id uuid,
  unit_id uuid,
  unit_name text,
  units_per_pack bigint,
  quantity bigint,
  base_quantity bigint,
  cost_price bigint,
  total_cost bigint,
  currency text,
  expiry_date text,
  received_at text,
  note text
);
alter table public.restocks add column if not exists business_id uuid;
alter table public.restocks add column if not exists created_at text;
alter table public.restocks add column if not exists updated_at text;
alter table public.restocks add column if not exists updated_by text;
alter table public.restocks add column if not exists deleted_at text;
alter table public.restocks add column if not exists main_category_id uuid;
alter table public.restocks add column if not exists supplier_id uuid;
alter table public.restocks add column if not exists item_id uuid;
alter table public.restocks add column if not exists unit_id uuid;
alter table public.restocks add column if not exists unit_name text;
alter table public.restocks add column if not exists units_per_pack bigint;
alter table public.restocks add column if not exists quantity bigint;
alter table public.restocks add column if not exists base_quantity bigint;
alter table public.restocks add column if not exists cost_price bigint;
alter table public.restocks add column if not exists total_cost bigint;
alter table public.restocks add column if not exists currency text;
alter table public.restocks add column if not exists expiry_date text;
alter table public.restocks add column if not exists received_at text;
alter table public.restocks add column if not exists note text;
create index if not exists restocks_business_idx on public.restocks(business_id);
create index if not exists restocks_shop_idx on public.restocks(main_category_id);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  created_at text,
  updated_at text,
  updated_by text,
  deleted_at text,
  main_category_id uuid,
  category text,
  amount bigint,
  currency text,
  note text,
  spent_at text
);
alter table public.expenses add column if not exists business_id uuid;
alter table public.expenses add column if not exists created_at text;
alter table public.expenses add column if not exists updated_at text;
alter table public.expenses add column if not exists updated_by text;
alter table public.expenses add column if not exists deleted_at text;
alter table public.expenses add column if not exists main_category_id uuid;
alter table public.expenses add column if not exists category text;
alter table public.expenses add column if not exists amount bigint;
alter table public.expenses add column if not exists currency text;
alter table public.expenses add column if not exists note text;
alter table public.expenses add column if not exists spent_at text;
create index if not exists expenses_business_idx on public.expenses(business_id);
create index if not exists expenses_shop_idx on public.expenses(main_category_id);

create table if not exists public.analytics_snapshots (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  period_type text,
  period_start text,
  main_category_id uuid,
  currency text,
  total_sales bigint,
  total_cost bigint,
  profit bigint,
  items_sold bigint,
  stock_value bigint,
  created_at text
);
alter table public.analytics_snapshots add column if not exists business_id uuid;
alter table public.analytics_snapshots add column if not exists period_type text;
alter table public.analytics_snapshots add column if not exists period_start text;
alter table public.analytics_snapshots add column if not exists main_category_id uuid;
alter table public.analytics_snapshots add column if not exists currency text;
alter table public.analytics_snapshots add column if not exists total_sales bigint;
alter table public.analytics_snapshots add column if not exists total_cost bigint;
alter table public.analytics_snapshots add column if not exists profit bigint;
alter table public.analytics_snapshots add column if not exists items_sold bigint;
alter table public.analytics_snapshots add column if not exists stock_value bigint;
alter table public.analytics_snapshots add column if not exists created_at text;
create index if not exists analytics_snapshots_business_idx on public.analytics_snapshots(business_id);
create index if not exists analytics_snapshots_shop_idx on public.analytics_snapshots(main_category_id);

create table if not exists public.exchange_rates (
  id uuid primary key default gen_random_uuid(),
  business_id uuid,
  base text,
  quote text,
  rate double precision,
  source text,
  fetched_at text
);
alter table public.exchange_rates add column if not exists business_id uuid;
alter table public.exchange_rates add column if not exists base text;
alter table public.exchange_rates add column if not exists quote text;
alter table public.exchange_rates add column if not exists rate double precision;
alter table public.exchange_rates add column if not exists source text;
alter table public.exchange_rates add column if not exists fetched_at text;
create index if not exists exchange_rates_business_idx on public.exchange_rates(business_id);

-- Invite codes (online only, not synced to phones).
create table if not exists public.invites (
  code text primary key,
  business_id uuid not null,
  role text not null default 'staff',
  permissions text not null default '[]',
  shop_ids text not null default '[]',
  created_by text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_by text,
  used_at timestamptz
);

-- ---------------------------------------------------------------- access helpers
create or replace function public.is_member(bid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from members m
    where m.business_id = bid and m.user_id = auth.uid()::text and m.deleted_at is null)
$$;

create or replace function public.is_owner(bid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from members m
    where m.business_id = bid and m.user_id = auth.uid()::text
      and m.role = 'owner' and m.deleted_at is null)
$$;

-- Owners reach every shop. Staff reach the shops in members.shop_ids
-- (a JSON list); an empty list means all shops.
create or replace function public.can_use_shop(bid uuid, shop uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select shop is null or exists (
    select 1 from members m
    where m.business_id = bid and m.user_id = auth.uid()::text and m.deleted_at is null
      and (m.role = 'owner'
           or coalesce(m.shop_ids, '[]') in ('', '[]')
           or (m.shop_ids::jsonb ? shop::text)))
$$;

-- ---------------------------------------------------------------- business setup
-- Called once by the owner's phone. Uses the business id the phone already has,
-- so everything recorded before sign-in uploads into this business.
create or replace function public.create_business(
  p_id uuid, p_name text, p_currency text, p_display_name text)
returns void language plpgsql security definer set search_path = public as $$
declare uid text := auth.uid()::text;
begin
  if uid is null then raise exception 'Sign in first'; end if;
  if exists (select 1 from businesses where id = p_id) then
    if not exists (select 1 from members where business_id = p_id and user_id = uid
                   and role = 'owner' and deleted_at is null) then
      raise exception 'This business belongs to another account';
    end if;
    return;
  end if;
  insert into businesses (id, name, owner_id, default_currency, report_currency, created_at, updated_at)
  values (p_id, p_name, uid, p_currency, p_currency, now_iso(), now_iso());
  insert into members (id, business_id, user_id, display_name, role, permissions, shop_ids,
                       created_at, updated_at, updated_by)
  values (gen_random_uuid(), p_id, uid, p_display_name, 'owner', '[]', '[]', now_iso(), now_iso(), uid);
end $$;

-- Owner creates an invite; returns the 6-character code to share.
create or replace function public.create_invite(
  p_business uuid, p_permissions text, p_shop_ids text)
returns text language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not is_owner(p_business) then raise exception 'Only the owner can invite staff'; end if;
  loop
    -- 6 characters from md5 (0-9, a-f), with 0 and 1 swapped out to avoid O/I confusion
    c := upper(substr(translate(md5(random()::text || clock_timestamp()::text), '01', 'xy'), 1, 6));
    exit when not exists (select 1 from invites where code = c);
  end loop;
  insert into invites (code, business_id, role, permissions, shop_ids, created_by)
  values (c, p_business, 'staff', coalesce(p_permissions, '[]'), coalesce(p_shop_ids, '[]'), auth.uid()::text);
  return c;
end $$;

-- Staff phone joins with a code; returns the business id.
create or replace function public.join_business(p_code text, p_display_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare inv invites; uid text := auth.uid()::text;
begin
  if uid is null then raise exception 'Sign in first'; end if;
  select * into inv from invites
  where code = upper(trim(p_code)) and used_at is null and expires_at > now();
  if not found then raise exception 'This invite code is not valid or has expired'; end if;
  if not exists (select 1 from members where business_id = inv.business_id
                 and user_id = uid and deleted_at is null) then
    insert into members (id, business_id, user_id, display_name, role, permissions, shop_ids,
                         created_at, updated_at, updated_by)
    values (gen_random_uuid(), inv.business_id, uid, p_display_name, inv.role,
            inv.permissions, inv.shop_ids, now_iso(), now_iso(), uid);
  end if;
  update invites set used_by = uid, used_at = now() where code = inv.code;
  return inv.business_id;
end $$;

-- Businesses this account belongs to (used right after sign-in).
create or replace function public.my_businesses()
returns table (business_id uuid, name text, role text)
language sql stable security definer set search_path = public as $$
  select m.business_id, b.name, m.role from members m
  join businesses b on b.id = m.business_id
  where m.user_id = auth.uid()::text and m.deleted_at is null
  order by b.name
$$;

grant execute on function public.create_business(uuid, text, text, text) to authenticated;
grant execute on function public.create_invite(uuid, text, text) to authenticated;
grant execute on function public.join_business(text, text) to authenticated;
grant execute on function public.my_businesses() to authenticated;

-- ---------------------------------------------------------------- row level security
alter table public.invites enable row level security;
drop policy if exists invites_owner on public.invites;
create policy invites_owner on public.invites for all
  using (is_owner(business_id)) with check (is_owner(business_id));

alter table public.businesses enable row level security;
drop policy if exists businesses_read on public.businesses;
create policy businesses_read on public.businesses for select using (is_member(id));
drop policy if exists businesses_insert on public.businesses;
create policy businesses_insert on public.businesses for insert
  with check (owner_id = auth.uid()::text);
drop policy if exists businesses_update on public.businesses;
create policy businesses_update on public.businesses for update
  using (is_owner(id)) with check (is_owner(id));

alter table public.members enable row level security;
drop policy if exists members_read on public.members;
create policy members_read on public.members for select using (is_member(business_id));
drop policy if exists members_update on public.members;
create policy members_update on public.members for update
  using (is_owner(business_id)) with check (is_owner(business_id));
-- Members are added only through create_business / join_business.

alter table public.main_categories enable row level security;
drop policy if exists shops_read on public.main_categories;
create policy shops_read on public.main_categories for select using (is_member(business_id));
drop policy if exists shops_insert on public.main_categories;
create policy shops_insert on public.main_categories for insert with check (is_owner(business_id));
drop policy if exists shops_update on public.main_categories;
create policy shops_update on public.main_categories for update
  using (is_owner(business_id)) with check (is_owner(business_id));

alter table public.item_categories enable row level security;
drop policy if exists item_categories_read on public.item_categories;
create policy item_categories_read on public.item_categories for select using (is_member(business_id));
drop policy if exists item_categories_insert on public.item_categories;
create policy item_categories_insert on public.item_categories for insert with check (is_member(business_id) and can_use_shop(business_id, main_category_id));
drop policy if exists item_categories_update on public.item_categories;
create policy item_categories_update on public.item_categories for update using (is_member(business_id) and can_use_shop(business_id, main_category_id)) with check (is_member(business_id) and can_use_shop(business_id, main_category_id));

alter table public.items enable row level security;
drop policy if exists items_read on public.items;
create policy items_read on public.items for select using (is_member(business_id));
drop policy if exists items_insert on public.items;
create policy items_insert on public.items for insert with check (is_member(business_id) and can_use_shop(business_id, main_category_id));
drop policy if exists items_update on public.items;
create policy items_update on public.items for update using (is_member(business_id) and can_use_shop(business_id, main_category_id)) with check (is_member(business_id) and can_use_shop(business_id, main_category_id));

alter table public.item_units enable row level security;
drop policy if exists item_units_read on public.item_units;
create policy item_units_read on public.item_units for select using (is_member(business_id));
drop policy if exists item_units_insert on public.item_units;
create policy item_units_insert on public.item_units for insert with check (is_member(business_id));
drop policy if exists item_units_update on public.item_units;
create policy item_units_update on public.item_units for update using (is_member(business_id)) with check (is_member(business_id));

alter table public.price_history enable row level security;
drop policy if exists price_history_read on public.price_history;
create policy price_history_read on public.price_history for select using (is_member(business_id));
drop policy if exists price_history_insert on public.price_history;
create policy price_history_insert on public.price_history for insert with check (is_member(business_id));
drop policy if exists price_history_update on public.price_history;
create policy price_history_update on public.price_history for update using (is_member(business_id)) with check (is_member(business_id));

alter table public.suppliers enable row level security;
drop policy if exists suppliers_read on public.suppliers;
create policy suppliers_read on public.suppliers for select using (is_member(business_id));
drop policy if exists suppliers_insert on public.suppliers;
create policy suppliers_insert on public.suppliers for insert with check (is_member(business_id));
drop policy if exists suppliers_update on public.suppliers;
create policy suppliers_update on public.suppliers for update using (is_member(business_id)) with check (is_member(business_id));

alter table public.item_suppliers enable row level security;
drop policy if exists item_suppliers_read on public.item_suppliers;
create policy item_suppliers_read on public.item_suppliers for select using (is_member(business_id));
drop policy if exists item_suppliers_insert on public.item_suppliers;
create policy item_suppliers_insert on public.item_suppliers for insert with check (is_member(business_id));
drop policy if exists item_suppliers_update on public.item_suppliers;
create policy item_suppliers_update on public.item_suppliers for update using (is_member(business_id)) with check (is_member(business_id));

alter table public.customers enable row level security;
drop policy if exists customers_read on public.customers;
create policy customers_read on public.customers for select using (is_member(business_id));
drop policy if exists customers_insert on public.customers;
create policy customers_insert on public.customers for insert with check (is_member(business_id));
drop policy if exists customers_update on public.customers;
create policy customers_update on public.customers for update using (is_member(business_id)) with check (is_member(business_id));

alter table public.sales enable row level security;
drop policy if exists sales_read on public.sales;
create policy sales_read on public.sales for select using (is_member(business_id));
drop policy if exists sales_insert on public.sales;
create policy sales_insert on public.sales for insert with check (is_member(business_id) and can_use_shop(business_id, main_category_id));
drop policy if exists sales_update on public.sales;
create policy sales_update on public.sales for update using (is_member(business_id) and can_use_shop(business_id, main_category_id)) with check (is_member(business_id) and can_use_shop(business_id, main_category_id));

alter table public.sale_items enable row level security;
drop policy if exists sale_items_read on public.sale_items;
create policy sale_items_read on public.sale_items for select using (is_member(business_id));
drop policy if exists sale_items_insert on public.sale_items;
create policy sale_items_insert on public.sale_items for insert with check (is_member(business_id));
drop policy if exists sale_items_update on public.sale_items;
create policy sale_items_update on public.sale_items for update using (is_member(business_id)) with check (is_member(business_id));

alter table public.payments enable row level security;
drop policy if exists payments_read on public.payments;
create policy payments_read on public.payments for select using (is_member(business_id));
drop policy if exists payments_insert on public.payments;
create policy payments_insert on public.payments for insert with check (is_member(business_id));
drop policy if exists payments_update on public.payments;
create policy payments_update on public.payments for update using (is_member(business_id)) with check (is_member(business_id));

alter table public.stock_movements enable row level security;
drop policy if exists stock_movements_read on public.stock_movements;
create policy stock_movements_read on public.stock_movements for select using (is_member(business_id));
drop policy if exists stock_movements_insert on public.stock_movements;
create policy stock_movements_insert on public.stock_movements for insert with check (is_member(business_id) and can_use_shop(business_id, main_category_id));
drop policy if exists stock_movements_update on public.stock_movements;
create policy stock_movements_update on public.stock_movements for update using (is_member(business_id) and can_use_shop(business_id, main_category_id)) with check (is_member(business_id) and can_use_shop(business_id, main_category_id));

alter table public.restocks enable row level security;
drop policy if exists restocks_read on public.restocks;
create policy restocks_read on public.restocks for select using (is_member(business_id));
drop policy if exists restocks_insert on public.restocks;
create policy restocks_insert on public.restocks for insert with check (is_member(business_id) and can_use_shop(business_id, main_category_id));
drop policy if exists restocks_update on public.restocks;
create policy restocks_update on public.restocks for update using (is_member(business_id) and can_use_shop(business_id, main_category_id)) with check (is_member(business_id) and can_use_shop(business_id, main_category_id));

alter table public.expenses enable row level security;
drop policy if exists expenses_read on public.expenses;
create policy expenses_read on public.expenses for select using (is_member(business_id));
drop policy if exists expenses_insert on public.expenses;
create policy expenses_insert on public.expenses for insert with check (is_member(business_id) and can_use_shop(business_id, main_category_id));
drop policy if exists expenses_update on public.expenses;
create policy expenses_update on public.expenses for update using (is_member(business_id) and can_use_shop(business_id, main_category_id)) with check (is_member(business_id) and can_use_shop(business_id, main_category_id));

alter table public.analytics_snapshots enable row level security;
drop policy if exists analytics_snapshots_read on public.analytics_snapshots;
create policy analytics_snapshots_read on public.analytics_snapshots for select using (is_member(business_id));
drop policy if exists analytics_snapshots_insert on public.analytics_snapshots;
create policy analytics_snapshots_insert on public.analytics_snapshots for insert with check (is_member(business_id) and can_use_shop(business_id, main_category_id));
drop policy if exists analytics_snapshots_update on public.analytics_snapshots;
create policy analytics_snapshots_update on public.analytics_snapshots for update using (is_member(business_id) and can_use_shop(business_id, main_category_id)) with check (is_member(business_id) and can_use_shop(business_id, main_category_id));

alter table public.exchange_rates enable row level security;
drop policy if exists exchange_rates_read on public.exchange_rates;
create policy exchange_rates_read on public.exchange_rates for select using (is_member(business_id));
drop policy if exists exchange_rates_insert on public.exchange_rates;
create policy exchange_rates_insert on public.exchange_rates for insert with check (is_member(business_id));
drop policy if exists exchange_rates_update on public.exchange_rates;
create policy exchange_rates_update on public.exchange_rates for update using (is_member(business_id)) with check (is_member(business_id));

-- ---------------------------------------------------------------- PowerSync
-- PowerSync reads changes through this publication.
drop publication if exists powersync;
create publication powersync for table public.businesses, public.members, public.main_categories, public.item_categories, public.items, public.item_units, public.price_history, public.suppliers, public.item_suppliers, public.customers, public.sales, public.sale_items, public.payments, public.stock_movements, public.restocks, public.expenses, public.analytics_snapshots, public.exchange_rates;
