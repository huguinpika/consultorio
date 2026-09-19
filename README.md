# Reserva de salas · Consultório

Next.js 16 (App Router) + TypeScript + Tailwind 4 + Supabase (Postgres + Auth) + Vercel.

## Status: Etapa 1 (fundação) ✅
Banco, RLS, regras anti-conflito, autenticação, proteção de rotas por função, cadastro com aprovação.
As telas de agenda/dashboard são placeholders (Etapas 2 e 3).

## Como rodar

1. **Supabase**: crie um projeto em supabase.com (plano gratuito). Região: São Paulo.
2. **Banco**: no *SQL Editor*, execute nesta ordem:
   1. `supabase/migrations/20260919000001_foundation.sql`
   2. `supabase/seed.sql` (2 salas, funcionamento 07h–22h todos os dias, regras padrão)
3. **Auth** (*Authentication → Providers/Settings*):
   - Mantenha **Confirm email** ligado.
   - *Site URL*: `http://localhost:3000` (depois, o domínio da Vercel).
   - Em *Email Templates → Confirm signup*, troque o link por:
     `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=signup`
   - Senha mínima: 10 caracteres.
4. **Variáveis**: `cp .env.example .env.local` e preencha URL e chave `anon` (Project Settings → API).
5. `npm install && npm run dev` → http://localhost:3000
6. **Crie a conta da administradora** pelo `/cadastro` e, no SQL Editor, promova-a:
   ```sql
   update public.profiles set role = 'ADMIN', is_active = true where email = 'EMAIL-DA-ADMIN';
   ```
   (Ninguém vira admin pelo site: o cadastro sempre cria PROFESSIONAL inativo.)
7. **Concluir reservas passadas automaticamente** (ative a extensão `pg_cron` em *Database → Extensions*):
   ```sql
   select cron.schedule('complete-reservations', '*/15 * * * *', $$select public.complete_past_reservations()$$);
   ```

## Testes do banco
`psql -v ON_ERROR_STOP=1 -f supabase/tests/conflicts.test.sql` (rodam em transação e são desfeitos).
Cobrem: conflitos (idêntico, parcial, adjacente, outra sala), horário de funcionamento, passado/antecedência,
duração, bloqueios, RLS por função, usuário inativo, cancelamento, prazo de cancelamento.

## Decisões de arquitetura
- **Conflito**: *exclusion constraint* GiST em `reservations` (sala + intervalo `[início, fim)`), só para
  reservas `confirmed`/`completed`. É atômica: duas requisições simultâneas → uma falha com SQLSTATE `23P01`.
- **Regras de negócio no banco** (triggers): funcionamento, bloqueios, duração, antecedência, passado.
  Assim nenhuma tela, API ou script consegue burlá-las. Os erros carregam um código em `DETAIL`
  (`OUTSIDE_HOURS`, `BLOCKED`…) que `lib/reservation-errors.ts` converte em mensagem amigável.
- **Três camadas de proteção**: `proxy.ts` (exige login) → layouts do servidor (`lib/auth.ts`: aprovado / admin) → **RLS**.
- **Privacidade**: profissionais veem a ocupação das salas via `get_room_occupancy()`, que devolve só
  sala + horário (nunca nomes). Não existe nenhum campo de paciente; `notes` tem até 200 caracteres.
- **Fuso**: horários em UTC no banco; regras avaliadas em `America/Sao_Paulo`.
- Admin pode registrar reservas no passado e passar por cima de limites de duração/antecedência, mas **nunca**
  por cima de conflito, horário de funcionamento ou bloqueio (para exceções, ajuste horários/bloqueios).

## Próximas etapas
2. Agenda (calendário + salas + horários livres), nova reserva, minhas reservas, editar/cancelar.
3. Painel da administradora: dashboard, profissionais (aprovar/desativar), horários e bloqueios, configurações.
4. Design premium, mobile, animações.
5. Relatórios, e-mails de notificação, endurecimento, base para pagamentos.
