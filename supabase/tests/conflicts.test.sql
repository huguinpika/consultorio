-- Testes das regras do banco. Rode com: psql -v ON_ERROR_STOP=1 -f supabase/tests/conflicts.test.sql
-- (tudo é desfeito no final com ROLLBACK)
begin;

-- helpers (removidos pelo rollback)
create function public.__t_at(d int, h int, m int default 0) returns timestamptz language sql stable as $$
  select ((date_trunc('day', now() at time zone 'America/Sao_Paulo') + make_interval(days => d, hours => h, mins => m))
          at time zone 'America/Sao_Paulo') $$;

create function public.__t_login(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, true) $$;

-- executa um comando e exige que falhe com o SQLSTATE ou o DETAIL esperado
create function public.__t_expect(cmd text, expected text) returns void language plpgsql as $$
declare st text; dt text;
begin
  begin
    execute cmd;
  exception when others then
    get stacked diagnostics dt = pg_exception_detail;
    st := sqlstate;
    if st = expected or dt = expected then return; end if;
    raise exception 'FALHA: esperava [%] mas veio sqlstate=% detail=% msg=% | cmd=%', expected, st, dt, sqlerrm, cmd;
  end;
  raise exception 'FALHA: esperava erro [%] mas o comando funcionou | cmd=%', expected, cmd;
end $$;

grant execute on function public.__t_at(int,int,int), public.__t_login(uuid), public.__t_expect(text,text) to authenticated;

-- usuários: A = admin, B e C = profissionais ativos, D = inativo
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'admin@x.com', '{"full_name":"Admin"}'),
  ('00000000-0000-0000-0000-00000000000b', 'b@x.com',     '{"full_name":"Psicologo B"}'),
  ('00000000-0000-0000-0000-00000000000c', 'c@x.com',     '{"full_name":"Psicologo C"}'),
  ('00000000-0000-0000-0000-00000000000d', 'd@x.com',     '{"full_name":"Psicologo D"}');

-- cadastro novo nasce PROFESSIONAL e inativo
do $$ begin
  assert (select bool_and(role = 'PROFESSIONAL' and not is_active) from public.profiles), 'novos perfis devem ser inativos';
end $$;
update public.profiles set role = 'ADMIN', is_active = true where email = 'admin@x.com';
update public.profiles set is_active = true where email in ('b@x.com', 'c@x.com');

create temp table ctx as
  select (select id from public.rooms where name = 'Sala 1') as r1,
         (select id from public.rooms where name = 'Sala 2') as r2;
grant select on ctx to authenticated;

set local role authenticated;

-- ===== 1) reserva válida =====
select public.__t_login('00000000-0000-0000-0000-00000000000b');
insert into public.reservations (professional_id, room_id, start_at, end_at)
  select '00000000-0000-0000-0000-00000000000b', r1, public.__t_at(3,14), public.__t_at(3,15) from ctx;

-- ===== 2) conflitos (garantia do banco) =====
select public.__t_login('00000000-0000-0000-0000-00000000000c');
select public.__t_expect(format($f$insert into public.reservations (professional_id, room_id, start_at, end_at)
  values (%L, %L, %L, %L)$f$, '00000000-0000-0000-0000-00000000000c', (select r1 from ctx), public.__t_at(3,14), public.__t_at(3,15)), '23P01');
select public.__t_expect(format($f$insert into public.reservations (professional_id, room_id, start_at, end_at)
  values (%L, %L, %L, %L)$f$, '00000000-0000-0000-0000-00000000000c', (select r1 from ctx), public.__t_at(3,13), public.__t_at(3,15)), '23P01');
select public.__t_expect(format($f$insert into public.reservations (professional_id, room_id, start_at, end_at)
  values (%L, %L, %L, %L)$f$, '00000000-0000-0000-0000-00000000000c', (select r1 from ctx), public.__t_at(3,14), public.__t_at(3,16)), '23P01');

-- outra sala no mesmo horário: OK; horário adjacente na mesma sala: OK
insert into public.reservations (professional_id, room_id, start_at, end_at)
  select '00000000-0000-0000-0000-00000000000c', r2, public.__t_at(3,14), public.__t_at(3,15) from ctx;
insert into public.reservations (professional_id, room_id, start_at, end_at)
  select '00000000-0000-0000-0000-00000000000c', r1, public.__t_at(3,15), public.__t_at(3,16) from ctx;

-- ===== 3) regras de horário =====
select public.__t_expect(format($f$insert into public.reservations (professional_id, room_id, start_at, end_at)
  values (%L, %L, %L, %L)$f$, '00000000-0000-0000-0000-00000000000c', (select r1 from ctx), public.__t_at(4,6), public.__t_at(4,7)), 'OUTSIDE_HOURS');
select public.__t_expect(format($f$insert into public.reservations (professional_id, room_id, start_at, end_at)
  values (%L, %L, %L, %L)$f$, '00000000-0000-0000-0000-00000000000c', (select r1 from ctx), public.__t_at(4,21), public.__t_at(4,23)), 'OUTSIDE_HOURS');
select public.__t_expect(format($f$insert into public.reservations (professional_id, room_id, start_at, end_at)
  values (%L, %L, %L, %L)$f$, '00000000-0000-0000-0000-00000000000c', (select r1 from ctx), public.__t_at(4,14,30), public.__t_at(4,15,30)), 'INVALID_START');
select public.__t_expect(format($f$insert into public.reservations (professional_id, room_id, start_at, end_at)
  values (%L, %L, %L, %L)$f$, '00000000-0000-0000-0000-00000000000c', (select r1 from ctx), public.__t_at(4,10), public.__t_at(4,15)), 'DURATION_LIMIT');
select public.__t_expect(format($f$insert into public.reservations (professional_id, room_id, start_at, end_at)
  values (%L, %L, %L, %L)$f$, '00000000-0000-0000-0000-00000000000c', (select r1 from ctx), public.__t_at(-1,10), public.__t_at(-1,11)), 'PAST');
select public.__t_expect(format($f$insert into public.reservations (professional_id, room_id, start_at, end_at)
  values (%L, %L, %L, %L)$f$, '00000000-0000-0000-0000-00000000000c', (select r1 from ctx), public.__t_at(90,10), public.__t_at(90,11)), 'TOO_FAR');
select public.__t_expect(format($f$insert into public.reservations (professional_id, room_id, start_at, end_at)
  values (%L, %L, %L, %L)$f$, '00000000-0000-0000-0000-00000000000c', (select r1 from ctx), public.__t_at(4,20), public.__t_at(5,8)), 'DURATION_LIMIT');

-- ===== 4) autorização =====
select public.__t_expect(format($f$insert into public.reservations (professional_id, room_id, start_at, end_at)
  values (%L, %L, %L, %L)$f$, '00000000-0000-0000-0000-00000000000b', (select r1 from ctx), public.__t_at(6,10), public.__t_at(6,11)), '42501');
do $$ begin assert (select count(*) from public.reservations) = 2, 'C deveria ver só as suas 2 reservas'; end $$;
select public.__t_login('00000000-0000-0000-0000-00000000000b');
do $$ begin assert (select count(*) from public.reservations) = 1, 'B deveria ver só a sua 1 reserva'; end $$;
select public.__t_expect($f$update public.profiles set role = 'ADMIN' where id = auth.uid()$f$, '42501');
select public.__t_login('00000000-0000-0000-0000-00000000000d');
select public.__t_expect($f$update public.profiles set is_active = true where id = auth.uid()$f$, '42501');
select public.__t_login('00000000-0000-0000-0000-00000000000b');
do $$
declare n int;
begin
  with u as (update public.settings set cancel_min_notice_hours = 0 returning 1) select count(*) into n from u;
  assert n = 0, 'profissional não pode alterar settings';
  with u as (update public.rooms set is_active = false returning 1) select count(*) into n from u;
  assert n = 0, 'profissional não pode alterar salas';
  with u as (delete from public.reservations returning 1) select count(*) into n from u;
  assert n = 0, 'profissional não pode excluir reservas';
end $$;
select public.__t_expect(format($f$insert into public.blocks (room_id, start_at, end_at) values (%L, %L, %L)$f$,
  (select r1 from ctx), public.__t_at(8,10), public.__t_at(8,11)), '42501');

-- ===== 5) ocupação anônima =====
select public.__t_login('00000000-0000-0000-0000-00000000000c');
do $$ begin
  assert (select count(*) from public.get_room_occupancy(public.__t_at(0,0), public.__t_at(10,0))) = 3, 'ocupação deveria listar as 3 reservas (inclusive a de B)';
  assert (select count(*) filter (where is_mine) from public.get_room_occupancy(public.__t_at(0,0), public.__t_at(10,0))) = 2, 'is_mine deveria marcar só as de C';
end $$;

-- ===== 6) usuário inativo =====
select public.__t_login('00000000-0000-0000-0000-00000000000d');
select public.__t_expect(format($f$insert into public.reservations (professional_id, room_id, start_at, end_at)
  values (%L, %L, %L, %L)$f$, '00000000-0000-0000-0000-00000000000d', (select r1 from ctx), public.__t_at(6,10), public.__t_at(6,11)), 'PROFESSIONAL_INACTIVE');
do $$ begin
  assert (select count(*) from public.get_room_occupancy(public.__t_at(0,0), public.__t_at(10,0))) = 0, 'inativo não vê ocupação';
  assert (select count(*) from public.rooms) = 0, 'inativo não lê salas';
end $$;

-- ===== 7) cancelamento libera o horário =====
select public.__t_login('00000000-0000-0000-0000-00000000000b');
update public.reservations set status = 'cancelled' where status = 'confirmed';
do $$ begin assert (select cancelled_at is not null from public.reservations limit 1), 'cancelled_at deve ser preenchido'; end $$;
select public.__t_login('00000000-0000-0000-0000-00000000000c');
insert into public.reservations (professional_id, room_id, start_at, end_at)
  select '00000000-0000-0000-0000-00000000000c', r1, public.__t_at(3,14), public.__t_at(3,15) from ctx;
select public.__t_login('00000000-0000-0000-0000-00000000000b');
select public.__t_expect($f$update public.reservations set status = 'confirmed'$f$, 'RESERVATION_LOCKED');

-- ===== 8) admin: bloqueios, criar para outros, registrar no passado =====
select public.__t_login('00000000-0000-0000-0000-00000000000a');
insert into public.blocks (room_id, start_at, end_at, reason) select r2, public.__t_at(7,0), public.__t_at(7,23), 'Manutenção' from ctx;
insert into public.reservations (professional_id, room_id, start_at, end_at)
  select '00000000-0000-0000-0000-00000000000b', r1, public.__t_at(-2,9), public.__t_at(-2,10) from ctx;
select public.__t_login('00000000-0000-0000-0000-00000000000c');
select public.__t_expect(format($f$insert into public.reservations (professional_id, room_id, start_at, end_at)
  values (%L, %L, %L, %L)$f$, '00000000-0000-0000-0000-00000000000c', (select r2 from ctx), public.__t_at(7,10), public.__t_at(7,11)), 'BLOCKED');

-- ===== 9) antecedência mínima para cancelar =====
reset role;
update public.settings set cancel_min_notice_hours = 24 * 30;
set local role authenticated;
select public.__t_login('00000000-0000-0000-0000-00000000000c');
select public.__t_expect($f$update public.reservations set status = 'cancelled' where status = 'confirmed'$f$, 'TOO_LATE');
update public.reservations set notes = 'sala com ar-condicionado' where status = 'confirmed';

reset role;
\echo '>>> TODOS OS TESTES PASSARAM'
rollback;
