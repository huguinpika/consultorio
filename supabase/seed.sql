-- Dados iniciais: 2 salas, configurações padrão e funcionamento diário 07h–22h.
-- Tudo isso poderá ser alterado depois pelo painel da administradora.
insert into public.settings (id) values (true) on conflict do nothing;

insert into public.rooms (name) values ('Sala 1'), ('Sala 2') on conflict (name) do nothing;

insert into public.business_hours (room_id, weekday, is_open, opens, closes)
select r.id, d, true, time '07:00', time '22:00'
  from public.rooms r, generate_series(0, 6) as d
on conflict do nothing;
