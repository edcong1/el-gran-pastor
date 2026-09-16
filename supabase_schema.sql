-- EL GRAN PASTOR V4 · SUPABASE
-- Ejecutar en SQL Editor de Supabase.
-- Coste inicial: 243.69 / 20 kg = 12.1845 €/kg
-- Stock inicial: Pastor 10 kg, Carnitas 5 kg, Cochinita 5 kg

create extension if not exists pgcrypto;

create table if not exists public.settings (
  id bigint primary key default 1,
  half_price numeric(10,2) not null default 25,
  one_price numeric(10,2) not null default 45,
  cost_kg numeric(10,4) not null default 12.1845,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

insert into public.settings(id,half_price,one_price,cost_kg)
values(1,25,45,12.1845)
on conflict(id) do nothing;

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid not null references auth.users(id),
  meat text not null check (meat in ('Pastor','Carnitas','Cochinita')),
  size_kg numeric(4,2) not null check (size_kg in (0.5,1)),
  qty integer not null check (qty > 0),
  kg_sold numeric(10,2) not null check (kg_sold > 0),
  payment_method text not null check (payment_method in ('Efectivo','Tarjeta','Bizum')),
  amount numeric(10,2) not null check (amount >= 0),
  cost numeric(10,2) not null check (cost >= 0),
  profit numeric(10,2) not null,
  notes text
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid not null references auth.users(id),
  concept text not null,
  amount numeric(10,2) not null check (amount >= 0),
  notes text
);

create table if not exists public.inventory (
  meat text primary key check (meat in ('Pastor','Carnitas','Cochinita')),
  initial_kg numeric(10,2) not null default 0,
  added_kg numeric(10,2) not null default 0,
  current_kg numeric(10,2) generated always as
    (initial_kg + added_kg) stored,
  updated_at timestamptz not null default now()
);

insert into public.inventory(meat,initial_kg,added_kg) values
('Pastor',10,0),('Carnitas',5,0),('Cochinita',5,0)
on conflict(meat) do nothing;

-- Registro de producciones/reposiciones de stock.
create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid not null references auth.users(id),
  meat text not null check (meat in ('Pastor','Carnitas','Cochinita')),
  kg numeric(10,2) not null,
  movement_type text not null check (movement_type in ('entrada','ajuste')),
  notes text
);

-- Vistas de stock: stock inicial + entradas - ventas.
create or replace view public.inventory_live as
select
  i.meat,
  i.initial_kg,
  coalesce(sum(case when m.movement_type='entrada' then m.kg when m.movement_type='ajuste' then m.kg else 0 end),0) as movements_kg,
  i.initial_kg
    + coalesce(sum(case when m.movement_type='entrada' then m.kg when m.movement_type='ajuste' then m.kg else 0 end),0)
    - coalesce((select sum(s.kg_sold) from public.sales s where s.meat=i.meat),0) as current_kg
from public.inventory i
left join public.inventory_movements m on m.meat=i.meat
group by i.meat,i.initial_kg;

-- RLS
alter table public.settings enable row level security;
alter table public.sales enable row level security;
alter table public.expenses enable row level security;
alter table public.inventory enable row level security;
alter table public.inventory_movements enable row level security;

drop policy if exists "authenticated read settings" on public.settings;
create policy "authenticated read settings" on public.settings for select to authenticated using (true);

drop policy if exists "authenticated update settings" on public.settings;
create policy "authenticated update settings" on public.settings for update to authenticated using (true) with check (true);

drop policy if exists "authenticated insert sales" on public.sales;
create policy "authenticated insert sales" on public.sales for insert to authenticated with check (auth.uid()=user_id);
drop policy if exists "authenticated read sales" on public.sales;
create policy "authenticated read sales" on public.sales for select to authenticated using (true);

drop policy if exists "authenticated insert expenses" on public.expenses;
create policy "authenticated insert expenses" on public.expenses for insert to authenticated with check (auth.uid()=user_id);
drop policy if exists "authenticated read expenses" on public.expenses;
create policy "authenticated read expenses" on public.expenses for select to authenticated using (true);

drop policy if exists "authenticated read inventory" on public.inventory;
create policy "authenticated read inventory" on public.inventory for select to authenticated using (true);
drop policy if exists "authenticated read movements" on public.inventory_movements;
create policy "authenticated read movements" on public.inventory_movements for select to authenticated using (true);
drop policy if exists "authenticated insert movements" on public.inventory_movements;
create policy "authenticated insert movements" on public.inventory_movements for insert to authenticated with check (auth.uid()=user_id);

-- Nota: para producción conviene restringir settings/inventory a un rol de administrador.
