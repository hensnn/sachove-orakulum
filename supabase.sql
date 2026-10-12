-- =====================================================================
--  Šachové Orákulum – nastavení databáze v Supabase
--  Celé to zkopíruj do Supabase → SQL Editor → New query a dej Run.
--  !!! Na řádku s 'ZMEN-ME' si nastav vlastní heslo pro zápis !!!
-- =====================================================================

-- Jeden řádek se všemi daty (hráči, partie, sázka)
create table if not exists public.sachy (
  id   int primary key default 1 check (id = 1),
  data jsonb not null default '{"settings":{"stake":100},"players":[],"games":[]}'
);
insert into public.sachy (id) values (1) on conflict do nothing;

-- Číst může každý, zapisovat přímo nikdo (jen přes funkci níže s heslem)
alter table public.sachy enable row level security;
drop policy if exists "cist muze kazdy" on public.sachy;
create policy "cist muze kazdy" on public.sachy for select to anon, authenticated using (true);

-- Heslo pro zápis (tabulka je zvenku neviditelná)
create table if not exists public.sachy_pin (pin text not null);
alter table public.sachy_pin enable row level security;
delete from public.sachy_pin;
insert into public.sachy_pin (pin) values ('ZMEN-ME');   -- <<< SEM SVOJE HESLO

-- Pomocná funkce: uklizený hráč
create or replace function public._sachy_hrac(p jsonb, p_id text)
returns jsonb language sql immutable as $$
  select case when left(trim(coalesce(p->>'name', '')), 24) = '' then null else
    jsonb_build_object(
      'id',    p_id,
      'name',  left(trim(p->>'name'), 24),
      'icon',  left(coalesce(nullif(p->>'icon', ''), '♟'), 8),
      'color', case when coalesce(p->>'color', '') ~ '^#[0-9a-fA-F]{6}$' then p->>'color' else '#ffffff' end)
  end
$$;

-- Pomocná funkce: uklizená partie (null = neplatná)
create or replace function public._sachy_partie(s jsonb, g jsonb, p_id text)
returns jsonb language sql immutable as $$
  select case when
      coalesce(g->>'white', '') <> '' and g->>'white' <> coalesce(g->>'black', '')
      and exists (select 1 from jsonb_array_elements(s->'players') x where x->>'id' = g->>'white')
      and exists (select 1 from jsonb_array_elements(s->'players') x where x->>'id' = g->>'black')
      and coalesce(g->>'result', '') in ('w', 'd', 'b')
      and coalesce(g->>'at', '') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$'
    then jsonb_build_object('id', p_id, 'white', g->>'white', 'black', g->>'black', 'result', g->>'result', 'at', g->>'at')
  end
$$;

-- Jediný vstup pro zápis: ověří heslo, provede akci, vrátí nová data
create or replace function public.sachy_akce(p_pin text, p_action text, p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  s   jsonb;
  n   jsonb;
  x   jsonb;
  nid text := substr(md5(random()::text || clock_timestamp()::text), 1, 12);
  pid text := nullif(p_data->>'id', '');
begin
  if not exists (select 1 from sachy_pin where pin = coalesce(p_pin, '')) then
    raise exception 'pin';
  end if;

  select data into s from sachy where id = 1 for update;

  if p_action = 'addGame' then
    x := _sachy_partie(s, p_data, nid);
    if x is null then raise exception 'Neplatná partie'; end if;
    s := jsonb_set(s, '{games}', (s->'games') || jsonb_build_array(x));

  elsif p_action = 'delGame' then
    s := jsonb_set(s, '{games}', coalesce((select jsonb_agg(g) from jsonb_array_elements(s->'games') g
                                            where g->>'id' <> coalesce(pid, '')), '[]'::jsonb));

  elsif p_action = 'savePlayer' then
    if pid is not null and exists (select 1 from jsonb_array_elements(s->'players') p where p->>'id' = pid) then
      x := _sachy_hrac(p_data, pid);
      if x is null then raise exception 'Hráč potřebuje jméno'; end if;
      s := jsonb_set(s, '{players}', (select jsonb_agg(case when p->>'id' = pid then x else p end)
                                      from jsonb_array_elements(s->'players') p));
    else
      x := _sachy_hrac(p_data, nid);
      if x is null then raise exception 'Hráč potřebuje jméno'; end if;
      s := jsonb_set(s, '{players}', (s->'players') || jsonb_build_array(x));
    end if;

  elsif p_action = 'delPlayer' then
    s := jsonb_set(s, '{players}', coalesce((select jsonb_agg(p) from jsonb_array_elements(s->'players') p
                                              where p->>'id' <> coalesce(pid, '')), '[]'::jsonb));
    s := jsonb_set(s, '{games}', coalesce((select jsonb_agg(g) from jsonb_array_elements(s->'games') g
                                            where g->>'white' <> coalesce(pid, '') and g->>'black' <> coalesce(pid, '')), '[]'::jsonb));

  elsif p_action = 'setStake' then
    s := jsonb_set(s, '{settings}', jsonb_build_object('stake',
           case when coalesce(p_data->>'stake', '') ~ '^-?\d{1,9}(\.\d+)?$' then round((p_data->>'stake')::numeric)::int else 0 end));

  elsif p_action = 'import' then
    x := p_data->'data';
    if jsonb_typeof(x->'players') is distinct from 'array' or jsonb_typeof(x->'games') is distinct from 'array' then
      raise exception 'Neplatný soubor';
    end if;
    n := jsonb_build_object('settings', jsonb_build_object('stake',
           case when coalesce(x->'settings'->>'stake', x->'settings'->>'win', '') ~ '^-?\d{1,9}(\.\d+)?$'
                then round(coalesce(x->'settings'->>'stake', x->'settings'->>'win')::numeric)::int else 100 end),
         'players', '[]'::jsonb, 'games', '[]'::jsonb);
    n := jsonb_set(n, '{players}', coalesce((select jsonb_agg(h) from (
           select _sachy_hrac(p, coalesce(nullif(left(p->>'id', 40), ''), md5(random()::text))) h
           from jsonb_array_elements(x->'players') p) t where h is not null), '[]'::jsonb));
    n := jsonb_set(n, '{games}', coalesce((select jsonb_agg(h) from (
           select _sachy_partie(n, g, coalesce(nullif(left(g->>'id', 40), ''), md5(random()::text))) h
           from jsonb_array_elements(x->'games') g) t where h is not null), '[]'::jsonb));
    s := n;

  elsif p_action = 'wipe' then
    s := '{"settings":{"stake":100},"players":[],"games":[]}'::jsonb;

  else
    raise exception 'Neznámá akce';
  end if;

  update sachy set data = s where id = 1;
  return s;
end
$$;

revoke all on function public.sachy_akce(text, text, jsonb) from public;
grant execute on function public.sachy_akce(text, text, jsonb) to anon, authenticated;
grant select on public.sachy to anon, authenticated;

-- Živé aktualizace (změna se hned objeví i ostatním)
do $$ begin
  alter publication supabase_realtime add table public.sachy;
exception when others then null;
end $$;
