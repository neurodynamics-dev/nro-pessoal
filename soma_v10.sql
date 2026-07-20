-- ============================================================
-- SOMA 10.0 — MIGRAÇÃO · NeuroDynamics
-- 1) Apontamento semanal: garante as colunas de resultado
--    (assiduidade/entregas), a marcação "tratado" e a foreign
--    key do item para o cabeçalho — a ausência dela derrubava
--    as consultas aninhadas e a ficha aparecia sem resultados.
-- 2) Contas: auto-provisionamento de perfis — a conta criada
--    na tela de login (ou já existente no Auth) ganha a linha
--    em perfis com papel 'leitura', vinculada ao membro pelo
--    e-mail do quadro (email_nro ou email_pessoal).
-- 3) Políticas: cada pessoa lê e cria o próprio perfil; um
--    gatilho blinda a auto-criação (sempre papel 'leitura',
--    nome/registro vindos do quadro — nunca escolhidos pelo
--    cliente). A gestão de papéis continua com os admins,
--    pelas políticas já existentes.
--
-- Pré-requisito: SOMA 9.0 aplicada.
-- Idempotente: pode rodar mais de uma vez sem duplicar nada.
-- COMO USAR: cole o arquivo INTEIRO no SQL Editor e Run.
-- ============================================================

-- ------------------------------------------------------------
-- 1. APONTAMENTO SEMANAL — resultado gravado e legível
-- ------------------------------------------------------------
alter table public.apontamento_itens add column if not exists assiduidade text;
alter table public.apontamento_itens add column if not exists entregas    text;
alter table public.apontamento_itens add column if not exists tratado     boolean not null default false;

-- valores aceitos (linhas antigas em branco continuam válidas)
alter table public.apontamento_itens drop constraint if exists apitens_assiduidade_check;
alter table public.apontamento_itens add constraint apitens_assiduidade_check
  check (assiduidade is null or assiduidade in ('SUFICIENTE','INSUFICIENTE'));
alter table public.apontamento_itens drop constraint if exists apitens_entregas_check;
alter table public.apontamento_itens add constraint apitens_entregas_check
  check (entregas is null or entregas in ('SUFICIENTE','INSUFICIENTE'));

-- foreign key do item para o cabeçalho ("not valid" para não travar
-- caso existam itens órfãos antigos; novos inserts são checados)
do $$
begin
  if not exists (select 1 from pg_constraint
                 where conname = 'apontamento_itens_apontamento_id_fkey'
                   and conrelid = 'public.apontamento_itens'::regclass) then
    alter table public.apontamento_itens
      add constraint apontamento_itens_apontamento_id_fkey
      foreign key (apontamento_id) references public.apontamentos(id)
      on delete cascade not valid;
  end if;
end $$;

-- acesso: qualquer pessoa autenticada registra e lê apontamentos
-- (a ficha do membro e o painel do Pessoal dependem da leitura);
-- concluir sinalização ("tratado") é ação de admin/pessoal.
-- Políticas permissivas ADICIONAIS — não removem nem restringem as
-- existentes; se a tabela estiver sem RLS, não têm efeito.
drop policy if exists ap_select_v10 on public.apontamentos;
create policy ap_select_v10 on public.apontamentos
  for select to authenticated using (true);
drop policy if exists ap_insert_v10 on public.apontamentos;
create policy ap_insert_v10 on public.apontamentos
  for insert to authenticated with check (true);

drop policy if exists api_select_v10 on public.apontamento_itens;
create policy api_select_v10 on public.apontamento_itens
  for select to authenticated using (true);
drop policy if exists api_insert_v10 on public.apontamento_itens;
create policy api_insert_v10 on public.apontamento_itens
  for insert to authenticated with check (true);
drop policy if exists api_update_v10 on public.apontamento_itens;
create policy api_update_v10 on public.apontamento_itens
  for update to authenticated
  using (public.papel_atual() in ('admin','pessoal'))
  with check (public.papel_atual() in ('admin','pessoal'));

-- ------------------------------------------------------------
-- 2. CONTAS — auto-provisionamento de perfis
-- ------------------------------------------------------------
-- localiza o membro do quadro pelo e-mail (NRO ou pessoal),
-- preferindo membros ativos
create or replace function public.fn_perfil_de_membro(p_email text)
returns table(registro integer, nome text)
language sql stable security definer
set search_path = public
as $$
  select m.registro, m.nome
  from membros m
  where lower(coalesce(m.email_nro,''))     = lower(coalesce(p_email,''))
     or lower(coalesce(m.email_pessoal,'')) = lower(coalesce(p_email,''))
  order by (m.status = 'Ativo') desc, m.registro
  limit 1;
$$;
revoke execute on function public.fn_perfil_de_membro(text) from public, anon;

-- toda conta nova no Auth ganha a linha em perfis (papel 'leitura');
-- qualquer falha aqui NÃO bloqueia o cadastro — o app completa no 1º login
create or replace function public.fn_novo_usuario()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare v record;
begin
  begin
    select * into v from public.fn_perfil_de_membro(new.email);
    insert into public.perfis (id, email, nome, registro, papel)
    values (new.id, new.email, v.nome, v.registro, 'leitura')
    on conflict (id) do nothing;
  exception when others then null;
  end;
  return new;
end $$;
revoke execute on function public.fn_novo_usuario() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.fn_novo_usuario();

-- contas do Auth criadas antes desta migração e ainda sem perfil
insert into public.perfis (id, email, nome, registro, papel)
select u.id, u.email, v.nome, v.registro, 'leitura'
from auth.users u
left join public.perfis p on p.id = u.id
left join lateral public.fn_perfil_de_membro(u.email) v on true
where p.id is null and u.email is not null
on conflict (id) do nothing;

-- ------------------------------------------------------------
-- 3. SEGURANÇA — o próprio usuário lê e cria seu perfil
-- ------------------------------------------------------------
-- blindagem da auto-criação: quando alguém insere o PRÓPRIO perfil
-- (tela de login), papel/nome/registro são impostos pelo banco —
-- um cliente adulterado não consegue se cadastrar como admin nem
-- se vincular a um registro alheio.
create or replace function public.fn_perfil_blindado()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare v record;
begin
  if auth.uid() is not null and new.id = auth.uid()
     and coalesce(public.papel_atual(),'') not in ('admin','pessoal') then
    new.papel := 'leitura';
    new.email := coalesce((select u.email from auth.users u where u.id = new.id), new.email);
    select * into v from public.fn_perfil_de_membro(new.email);
    new.nome := v.nome;
    new.registro := v.registro;
  end if;
  return new;
end $$;
revoke execute on function public.fn_perfil_blindado() from public, anon, authenticated;

drop trigger if exists tg_perfil_blindado on public.perfis;
create trigger tg_perfil_blindado before insert on public.perfis
  for each row execute function public.fn_perfil_blindado();

drop policy if exists perfis_self_select_v10 on public.perfis;
create policy perfis_self_select_v10 on public.perfis
  for select to authenticated using (id = auth.uid());
drop policy if exists perfis_self_insert_v10 on public.perfis;
create policy perfis_self_insert_v10 on public.perfis
  for insert to authenticated with check (id = auth.uid());

-- ------------------------------------------------------------
-- PRONTO. Conferências úteis:
--   1) papéis atuais:  select email, nome, papel, registro from perfis order by email;
--   2) contas sem vínculo com o quadro:
--      select email from perfis where registro is null;
--   3) para promover alguém: SOMA → Operações → Contas e perfis
--      (ou: update perfis set papel='pessoal' where email='fulano@...';)
-- ============================================================
