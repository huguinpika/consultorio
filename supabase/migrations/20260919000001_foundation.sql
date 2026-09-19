-- =====================================================================
-- FUNDAÇÃO: sistema de reservas de salas (consultório de psicologia)
-- Privacidade: NÃO existe nenhuma tabela/campo de paciente.
-- Fuso fixo: America/Sao_Paulo (horários armazenados em UTC/timestamptz).
-- =====================================================================

create extension if not exists btree_gist;

-- ---------- Tipos ----------
create type public.user_role as enum ('ADMIN', 'PROFESSIONAL');
create type public.reservation_status as enum ('confirmed', 'cancelled', 'completed');

-- ---------- Utilitário ----------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------- Tabelas ----------
-- profiles: 1 linha por usuário do Supabase Auth (senha fica só no Auth, com hash)
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null,
  full_name   text not null check (char_length(full_name) between 2 and 120),
  phone       text check (phone is null or char_length(phone) <= 30),
  role        public.user_role not null default 'PROFESSIONAL',
  is_active   boolean not null default false,   -- novos cadastros aguardam aprovação
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger trg_profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();

create table public.rooms (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

-- Configurações globais (linha única)
create table public.settings (
  id                        boolean primary key default true check (id),
  slot_minutes              int  not null default 60  check (slot_minutes in (15, 30, 60)),
  min_duration_minutes      int  not null default 60  check (min_duration_minutes > 0),
  max_duration_minutes      int  not null default 240 check (max_duration_minutes >= min_duration_minutes),
  max_days_ahead            int  not null default 60  check (max_days_ahead > 0),
  cancel_min_notice_hours   int  not null default 24  check (cancel_min_notice_hours >= 0),
  updated_at                timestamptz not null default now()
);
create trigger trg_settings_updated before update on public.settings
  for each row execute function public.set_updated_at();

-- Horário de funcionamento por sala e dia da semana (0 = domingo ... 6 = sábado)
create table public.business_hours (
  room_id  uuid not null references public.rooms (id) on delete cascade,
  weekday  smallint not null check (weekday between 0 and 6),
  is_open  boolean not null default true,
  opens    time not null,
  closes   time not null,
  primary key (room_id, weekday),
  check (closes > opens)
);

-- Bloqueios pontuais (feriado, manutenção). room_id nulo = todas as salas.
create table public.blocks (
  id         uuid primary key default gen_random_uuid(),
  room_id    uuid references public.rooms (id) on delete cascade,
  start_at   timestamptz not null,
  end_at     timestamptz not null,
  reason     text check (reason is null or char_length(reason) <= 200),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  check (end_at > start_at)
);
create index blocks_range_idx on public.blocks using gist (tstzrange(start_at, end_at));

create table public.reservations (
  id              uuid primary key default gen_random_uuid(),
  professional_id uuid not null references public.profiles (id) on delete restrict,
  room_id         uuid not null references public.rooms (id) on delete restrict,
  start_at        timestamptz not null,
  end_at          timestamptz not null,
  status          public.reservation_status not null default 'confirmed',
  notes           text check (notes is null or char_length(notes) <= 200),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  cancelled_at    timestamptz,
  check (end_at > start_at),

  -- >>> PROTEÇÃO CONTRA CONFLITOS (a garantia final vive no banco) <<<
  -- Duas reservas ativas (confirmada/concluída) não podem se sobrepor na mesma sala.
  -- Intervalo semiaberto [início, fim): 14–15h e 15–16h NÃO conflitam.
  constraint reservations_no_overlap exclude using gist (
    room_id with =,
    tstzrange(start_at, end_at, '[)') with &&
  ) where (status in ('confirmed', 'completed'))
);
create index reservations_professional_idx on public.reservations (professional_id, start_at desc);
create index reservations_status_start_idx on public.reservations (status, start_at);
create trigger trg_reservations_updated before update on public.reservations
  for each row execute function public.set_updated_at();

-- ---------- Funções de apoio (security definer p/ evitar recursão de RLS) ----------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role = 'ADMIN' and is_active)
$$;

create or replace function public.is_active_user()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and is_active)
$$;

-- Cria o profile automaticamente no cadastro. Sempre PROFESSIONAL e INATIVO:
-- ninguém consegue se autopromover a ADMIN pelo formulário de cadastro.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name, phone)
  values (
    new.id,
    new.email,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), split_part(new.email, '@', 1)),
    nullif(trim(new.raw_user_meta_data ->> 'phone'), '')
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Impede que um profissional altere role / ativo / e-mail do próprio perfil.
create or replace function public.protect_profile_columns()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if new.role is distinct from old.role
       or new.is_active is distinct from old.is_active
       or new.email is distinct from old.email
       or new.id is distinct from old.id then
      raise exception 'Alteração não permitida.' using errcode = '42501', detail = 'FORBIDDEN_COLUMN';
    end if;
  end if;
  return new;
end $$;
create trigger trg_profiles_protect before update on public.profiles
  for each row execute function public.protect_profile_columns();

-- ---------- Regras de permissão sobre reservas ----------
-- Profissional: só cria para si, só edita/cancela as suas (confirmadas) e respeitando a antecedência.
-- Admin (ou service role / SQL editor, onde auth.uid() é nulo): sem essas restrições.
create or replace function public.guard_reservation_changes()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  s public.settings%rowtype;
begin
  if new.status = 'cancelled' and (tg_op = 'INSERT' or old.status <> 'cancelled') then
    new.cancelled_at := now();
  end if;

  if auth.uid() is null or public.is_admin() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.professional_id <> auth.uid() then
      raise exception 'Você só pode reservar em seu próprio nome.' using errcode = '42501', detail = 'FORBIDDEN';
    end if;
    if new.status <> 'confirmed' then
      raise exception 'Status inválido.' using errcode = '42501', detail = 'FORBIDDEN';
    end if;
    return new;
  end if;

  -- UPDATE
  if new.professional_id <> old.professional_id then
    raise exception 'Alteração não permitida.' using errcode = '42501', detail = 'FORBIDDEN';
  end if;
  if old.status <> 'confirmed' then
    raise exception 'Esta reserva não pode mais ser alterada.' using detail = 'RESERVATION_LOCKED';
  end if;
  if new.status not in ('confirmed', 'cancelled') then
    raise exception 'Status inválido.' using errcode = '42501', detail = 'FORBIDDEN';
  end if;
  -- alterar só a observação é sempre permitido
  if new.status = 'confirmed' and new.room_id = old.room_id
     and new.start_at = old.start_at and new.end_at = old.end_at then
    return new;
  end if;

  select * into s from public.settings;
  if old.start_at - now() < make_interval(hours => s.cancel_min_notice_hours) then
    raise exception 'Prazo para alterar/cancelar encerrado (mínimo de % h de antecedência).', s.cancel_min_notice_hours
      using detail = 'TOO_LATE';
  end if;
  return new;
end $$;
create trigger trg_reservations_guard before insert or update on public.reservations
  for each row execute function public.guard_reservation_changes();

-- ---------- Regras de horário (funcionamento, bloqueios, duração, antecedência) ----------
-- Os erros trazem um código em "detail" para o app traduzir em mensagens amigáveis.
create or replace function public.validate_reservation()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  tz         constant text := 'America/Sao_Paulo';
  s          public.settings%rowtype;
  bh         public.business_hours%rowtype;
  privileged boolean := (auth.uid() is null) or public.is_admin();
  l_start    timestamp;
  l_end      timestamp;
  day0       timestamp;
  dur_min    numeric;
  start_min  numeric;
begin
  if new.status <> 'confirmed' then
    return new;
  end if;
  -- só revalida quando algo relevante mudou
  if tg_op = 'UPDATE' and old.status = 'confirmed'
     and new.room_id = old.room_id and new.start_at = old.start_at and new.end_at = old.end_at then
    return new;
  end if;

  select * into s from public.settings;

  if not exists (select 1 from public.rooms where id = new.room_id and is_active) then
    raise exception 'Sala indisponível.' using detail = 'ROOM_INACTIVE';
  end if;
  if not exists (select 1 from public.profiles where id = new.professional_id and is_active) then
    raise exception 'Profissional inativo.' using detail = 'PROFESSIONAL_INACTIVE';
  end if;

  l_start   := new.start_at at time zone tz;
  l_end     := new.end_at at time zone tz;
  day0      := date_trunc('day', l_start);
  dur_min   := extract(epoch from (new.end_at - new.start_at)) / 60;
  start_min := extract(epoch from (l_start - day0)) / 60;

  if mod(start_min, s.slot_minutes) <> 0 then
    raise exception 'O horário inicial deve ser múltiplo de % min.', s.slot_minutes using detail = 'INVALID_START';
  end if;
  if mod(dur_min, s.slot_minutes) <> 0 then
    raise exception 'A duração deve ser múltipla de % min.', s.slot_minutes using detail = 'INVALID_DURATION';
  end if;

  if not privileged then
    if new.start_at < now() then
      raise exception 'Não é possível reservar horários no passado.' using detail = 'PAST';
    end if;
    if new.start_at > now() + make_interval(days => s.max_days_ahead) then
      raise exception 'Reservas só podem ser feitas com até % dias de antecedência.', s.max_days_ahead using detail = 'TOO_FAR';
    end if;
    if dur_min < s.min_duration_minutes or dur_min > s.max_duration_minutes then
      raise exception 'Duração permitida: de % a % minutos.', s.min_duration_minutes, s.max_duration_minutes
        using detail = 'DURATION_LIMIT';
    end if;
  end if;

  -- horário de funcionamento (vale para todos, inclusive admin; para exceções, a admin usa "bloqueios" / ajusta horários)
  select * into bh from public.business_hours
   where room_id = new.room_id and weekday = extract(dow from l_start)::int;
  if not found or not bh.is_open then
    raise exception 'A sala não funciona neste dia.' using detail = 'CLOSED_DAY';
  end if;
  if (l_start - day0) < (bh.opens - time '00:00')
     or (l_end - day0) > (bh.closes - time '00:00') then
    raise exception 'Fora do horário de funcionamento.' using detail = 'OUTSIDE_HOURS';
  end if;

  if exists (
    select 1 from public.blocks b
     where (b.room_id is null or b.room_id = new.room_id)
       and tstzrange(b.start_at, b.end_at, '[)') && tstzrange(new.start_at, new.end_at, '[)')
  ) then
    raise exception 'Este horário está bloqueado.' using detail = 'BLOCKED';
  end if;

  return new;
end $$;
create trigger trg_reservations_validate before insert or update on public.reservations
  for each row execute function public.validate_reservation();

-- ---------- Ocupação anônima (o profissional vê o que está ocupado, sem nomes) ----------
create or replace function public.get_room_occupancy(p_from timestamptz, p_to timestamptz)
returns table (room_id uuid, start_at timestamptz, end_at timestamptz, kind text, is_mine boolean)
language sql stable security definer set search_path = public as $$
  select r.room_id, r.start_at, r.end_at, 'reservation'::text, (r.professional_id = auth.uid())
    from public.reservations r
   where public.is_active_user()
     and p_to - p_from <= interval '93 days'
     and r.status in ('confirmed', 'completed')
     and r.start_at < p_to and r.end_at > p_from
  union all
  select ro.id, b.start_at, b.end_at, 'block'::text, false
    from public.blocks b
    join public.rooms ro on (b.room_id is null or b.room_id = ro.id)
   where public.is_active_user()
     and p_to - p_from <= interval '93 days'
     and b.start_at < p_to and b.end_at > p_from
$$;

-- Marca como "concluída" as reservas confirmadas que já terminaram.
-- Agende com pg_cron (ver README) ou chame pelo servidor.
create or replace function public.complete_past_reservations()
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update public.reservations set status = 'completed'
   where status = 'confirmed' and end_at < now();
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------- Permissões de execução ----------
revoke execute on function
  public.is_admin(), public.is_active_user(), public.get_room_occupancy(timestamptz, timestamptz),
  public.complete_past_reservations(), public.handle_new_user(),
  public.protect_profile_columns(), public.guard_reservation_changes(), public.validate_reservation()
  from public, anon;
grant execute on function public.is_admin(), public.is_active_user(),
  public.get_room_occupancy(timestamptz, timestamptz) to authenticated;
revoke execute on function public.complete_past_reservations() from authenticated;

-- ---------- Row Level Security ----------
alter table public.profiles       enable row level security;
alter table public.rooms          enable row level security;
alter table public.settings       enable row level security;
alter table public.business_hours enable row level security;
alter table public.blocks         enable row level security;
alter table public.reservations   enable row level security;

-- profiles: cada um vê/edita o próprio (colunas sensíveis protegidas por trigger); admin vê/edita todos
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_update_admin on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- salas, horários, bloqueios, configurações: leitura para ativos; escrita só admin
create policy rooms_read on public.rooms for select to authenticated using (public.is_active_user());
create policy rooms_admin on public.rooms for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy settings_read on public.settings for select to authenticated using (public.is_active_user());
create policy settings_admin on public.settings for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy bh_read on public.business_hours for select to authenticated using (public.is_active_user());
create policy bh_admin on public.business_hours for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy blocks_read on public.blocks for select to authenticated using (public.is_active_user());
create policy blocks_admin on public.blocks for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- reservas: profissional só as próprias; admin todas; exclusão só admin
create policy res_select on public.reservations for select to authenticated
  using (professional_id = auth.uid() or public.is_admin());
create policy res_insert on public.reservations for insert to authenticated
  with check (public.is_admin() or (professional_id = auth.uid() and public.is_active_user()));
create policy res_update on public.reservations for update to authenticated
  using (public.is_admin() or (professional_id = auth.uid() and public.is_active_user()))
  with check (public.is_admin() or (professional_id = auth.uid() and public.is_active_user()));
create policy res_delete on public.reservations for delete to authenticated
  using (public.is_admin());
