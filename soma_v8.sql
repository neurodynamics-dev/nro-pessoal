-- ============================================================
-- SOMA 8.0 — MIGRAÇÃO · NeuroDynamics
-- Módulo de OKRs (Planejamento Estratégico): objetivos em
-- árvore (estratégico -> tático -> operacional), cada um com
-- responsáveis, prazo, status e comentários de acompanhamento.
-- A visão fica no SOMA · Gestão (index.html), aba "OKRs",
-- no mesmo estilo da visão de Organização (árvore centrada
-- no objetivo em foco).
--
-- Permissões:
--   consulta            -> qualquer autenticado (a estratégia é da casa)
--   criar / excluir     -> admin e pessoal
--   atualizar (status,
--     prazo, respons.)  -> admin, pessoal e os responsáveis do objetivo
--   comentar            -> qualquer autenticado
--
-- Inclui a carga inicial do Planejamento Estratégico 2026
-- (planilha OE / OT / OP + eixos). A carga só roda se a tabela
-- estiver vazia — depois disso, a gestão é toda pela ferramenta.
--
-- Pré-requisito: SOMA 7.0 aplicada.
-- Idempotente: pode rodar mais de uma vez sem duplicar nada.
-- COMO USAR: cole o arquivo INTEIRO no SQL Editor e Run.
-- ============================================================

-- ------------------------------------------------------------
-- 1. OBJETIVOS (árvore via pai_id; codigo é a chave "humana")
-- ------------------------------------------------------------
create table if not exists public.okr_objetivos (
  id            uuid primary key default gen_random_uuid(),
  codigo        text not null unique,          -- OE1, OT1.2, OP1.2.3…
  pai_id        uuid references public.okr_objetivos(id) on delete cascade,
  nivel         text not null default 'operacional'
                check (nivel in ('estrategico','tatico','operacional')),
  titulo        text not null,
  descricao     text,
  eixo          text,                          -- Tecnologia, Científico, Gestão…
  ano           integer not null default 2026, -- ciclo de planejamento
  responsaveis  integer[] not null default '{}', -- registros de membros
  prazo         date,
  status        text not null default 'Não iniciado'
                check (status in ('Não iniciado','Em andamento','Em risco','Concluído','Cancelado')),
  ordem         integer not null default 100,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists idx_okr_pai on public.okr_objetivos (pai_id, ordem);

drop trigger if exists tg_upd_okr on public.okr_objetivos;
create trigger tg_upd_okr before update on public.okr_objetivos
  for each row execute function public.fn_atualizado();

-- ------------------------------------------------------------
-- 2. COMENTÁRIOS (histórico de acompanhamento de cada objetivo;
--    tipo "sistema" registra mudanças de prazo e de status
--    feitas pela ferramenta)
-- ------------------------------------------------------------
create table if not exists public.okr_comentarios (
  id          uuid primary key default gen_random_uuid(),
  objetivo_id uuid not null references public.okr_objetivos(id) on delete cascade,
  autor       text not null,
  registro    integer references public.membros(registro) on delete set null,
  tipo        text not null default 'comentario'
              check (tipo in ('comentario','sistema')),
  texto       text not null,
  criado_em   timestamptz not null default now()
);
create index if not exists idx_okr_com on public.okr_comentarios (objetivo_id, criado_em);

-- ------------------------------------------------------------
-- 3. AUDITORIA (mesmo gatilho das demais tabelas do sistema)
-- ------------------------------------------------------------
drop trigger if exists tg_aud_okr on public.okr_objetivos;
create trigger tg_aud_okr after insert or update or delete on public.okr_objetivos
  for each row execute function public.fn_auditoria();
drop trigger if exists tg_aud_okrcom on public.okr_comentarios;
create trigger tg_aud_okrcom after insert or update or delete on public.okr_comentarios
  for each row execute function public.fn_auditoria();

-- ------------------------------------------------------------
-- 4. SEGURANÇA (RLS)
-- ------------------------------------------------------------
alter table public.okr_objetivos   enable row level security;
alter table public.okr_comentarios enable row level security;

-- admin/pessoal, ou perfil cujo registro está entre os responsáveis
create or replace function public.okr_pode_atualizar(r integer[])
returns boolean language sql stable security definer
set search_path = public
as $$
  select public.papel_atual() in ('admin','pessoal')
      or exists (select 1 from public.perfis p
                  where p.id = auth.uid() and p.registro = any(r));
$$;
grant execute on function public.okr_pode_atualizar(integer[]) to authenticated;

drop policy if exists okr_select on public.okr_objetivos;
create policy okr_select on public.okr_objetivos
  for select to authenticated using (true);
drop policy if exists okr_insert on public.okr_objetivos;
create policy okr_insert on public.okr_objetivos
  for insert to authenticated
  with check (public.papel_atual() in ('admin','pessoal'));
drop policy if exists okr_update on public.okr_objetivos;
create policy okr_update on public.okr_objetivos
  for update to authenticated
  using (public.okr_pode_atualizar(responsaveis))
  with check (public.okr_pode_atualizar(responsaveis));
drop policy if exists okr_delete on public.okr_objetivos;
create policy okr_delete on public.okr_objetivos
  for delete to authenticated
  using (public.papel_atual() in ('admin','pessoal'));

drop policy if exists okrcom_select on public.okr_comentarios;
create policy okrcom_select on public.okr_comentarios
  for select to authenticated using (true);
drop policy if exists okrcom_insert on public.okr_comentarios;
create policy okrcom_insert on public.okr_comentarios
  for insert to authenticated with check (true);
drop policy if exists okrcom_delete on public.okr_comentarios;
create policy okrcom_delete on public.okr_comentarios
  for delete to authenticated
  using (public.papel_atual() in ('admin','pessoal'));

-- ------------------------------------------------------------
-- 5. CARGA INICIAL — Planejamento Estratégico 2026
--    Prazos: Q1 = 31/03, Q2 = 30/06, Q3 = 30/09, Q4 = 31/12.
--    Objetivos táticos e estratégicos ficam com o prazo mais
--    distante entre os seus desdobramentos.
--    Só roda com a tabela vazia (não recria o que foi apagado).
-- ------------------------------------------------------------
do $$
begin
  if exists (select 1 from public.okr_objetivos) then
    return;
  end if;

  insert into public.okr_objetivos (codigo, nivel, titulo, eixo, prazo, ordem) values
    -- Objetivos estratégicos
    ('OE1','estrategico','Finalizar e validar entregas tecnológicas centrais',              null, null, 10),
    ('OE2','estrategico','Consolidar a NeuroDynamics como programa sustentável na UFMG',    null, null, 20),
    ('OE3','estrategico','Aumentar a produção científica e a relevância acadêmica',         null, null, 30),
    ('OE4','estrategico','Fortalecer marca, visibilidade e posicionamento público',         null, null, 40),
    ('OE5','estrategico','Captar recursos e consolidar parcerias estratégicas',             null, null, 50),
    ('OE6','estrategico','Criar ecossistema vivo de talentos e comunidade',                 null, null, 60),
    -- Objetivos táticos
    ('OT1.1','tatico','Finalizar entregas tecnológicas prioritárias',   null, null, 10),
    ('OT1.2','tatico','Construir protótipo funcional do FES-Recare',   null, null, 20),
    ('OT1.3','tatico','Concluir projeto FES BCI',                      null, null, 30),
    ('OT1.4','tatico','Cumprir demandas do BioProt',                   null, null, 40),
    ('OT1.5','tatico','Concluir projetos complementares',              null, null, 50),
    ('OT1.6','tatico','Finalizar estudos de autoencoder e BCI',        null, null, 60),
    ('OT2.1','tatico','Oficializar grupo de pesquisa',                 null, null, 10),
    ('OT2.2','tatico','Criar mecanismo de registro de membros',        null, null, 20),
    ('OT2.3','tatico','Estrutura física e governança',                 null, null, 30),
    ('OT3.1','tatico','Produção científica contínua',                  null, null, 10),
    ('OT4.1','tatico','Marca e identidade institucional',              null, null, 10),
    ('OT4.2','tatico','Comunicação contínua',                          null, null, 20),
    ('OT5.1','tatico','Estruturar setor de parcerias',                 null, null, 10),
    ('OT5.2','tatico','Consolidar rede estratégica de parceiros',      null, null, 20),
    ('OT6.1','tatico','Participar e desenvolver eventos',              null, null, 10),
    ('OT6.2','tatico','Melhorar quadro de membros',                    null, null, 20),
    ('OT6.3','tatico','Melhorar quadro de pacientes',                  null, null, 30),
    -- Objetivos operacionais
    ('OP1.1.1','operacional','Finalizar versão estável e documentada do FES-Connect até Q2',                              'Tecnologia','2026-06-30', 10),
    ('OP1.1.2','operacional','Concluir validação final do FES-Connect e iniciar testes até Q3',                           'Científico','2026-09-30', 20),
    ('OP1.1.3','operacional','Concluir FES-Connect (com Jonathan pedalando) até Q2',                                      'Tecnologia','2026-06-30', 30),
    ('OP1.2.1','operacional','Construir o protótipo funcional do FES-Recare (Ciclo Ergômetro + FES Cycling) até Q2',      'Tecnologia','2026-06-30', 10),
    ('OP1.2.2','operacional','Concluir desenvolvimento da funcionalidade de FES Cycling no Recare até Q1',                'Tecnologia','2026-03-31', 20),
    ('OP1.2.3','operacional','Concluir compra de material necessário até Q2',                                             'Tecnologia','2026-06-30', 30),
    ('OP1.2.4','operacional','Concluir desenvolvimento da funcionalidade de FES Respiratório no Recare até Q3',           'Tecnologia','2026-09-30', 40),
    ('OP1.3.1','operacional','Finalizar desenvolvimento da funcionalidade FES com BCI até Q1',                            'Tecnologia','2026-03-31', 10),
    ('OP1.3.2','operacional','Iniciar validação do FES BCI em Q2',                                                        'Científico','2026-06-30', 20),
    ('OP1.4.1','operacional','Cumprir demandas do BioProt até Q4',                                                        'Tecnologia','2026-12-31', 10),
    ('OP1.5.1','operacional','Concluir desenvolvimento das bicicletas ergométricas para experimento no Paulo de Tarso até Q2','Tecnologia','2026-06-30', 10),
    ('OP1.5.2','operacional','Concluir projeto da LLM para saúde até Q4',                                                 'Tecnologia','2026-12-31', 20),
    ('OP1.5.3','operacional','Finalizar estudos de autoencoder e BCI até Q2',                                             'Científico','2026-06-30', 10),
    ('OP2.1.1','operacional','Registrar grupo de pesquisa NeuroDynamics até Q2',                                          'Gestão','2026-06-30', 10),
    ('OP2.2.1','operacional','Emitir todos os certificados faltantes em Q1',                                              'Gestão','2026-03-31', 10),
    ('OP2.2.2','operacional','Implementar certificação para ≥ 30 voluntários até Q2',                                     'Gestão','2026-06-30', 20),
    ('OP2.2.3','operacional','Vincular todos os voluntários em Q1',                                                       'Gestão','2026-03-31', 30),
    ('OP2.2.4','operacional','Submeter edital de IC voluntária em Q1',                                                    'Gestão','2026-03-31', 40),
    ('OP2.3.1','operacional','Criar modelo de bolsas e orçamento até Q3',                                                 'Prospecção','2026-09-30', 10),
    ('OP2.3.2','operacional','Estruturar governança até Q2',                                                              'Gestão','2026-06-30', 20),
    ('OP2.3.3','operacional','Garantir espaço físico até Q3',                                                             'Gestão','2026-09-30', 30),
    ('OP3.1.1','operacional','Submeter 2 artigos até fim de Q2',                                                          'Científico','2026-06-30', 10),
    ('OP3.1.2','operacional','Submeter 2 artigos até fim de Q4',                                                          'Científico','2026-12-31', 20),
    ('OP3.1.3','operacional','Publicar artigo sobre FES BCI em Q2',                                                       'Científico','2026-06-30', 30),
    ('OP4.1.1','operacional','Produzir Media Kit + Pitch Deck até Q2',                                                    'Prospecção','2026-06-30', 10),
    ('OP4.1.2','operacional','Produzir Branding Book até Q2',                                                             'Gestão','2026-06-30', 20),
    ('OP4.2.1','operacional','Implementar 2 posts/semana + 2 vídeos/mês após Q1',                                         'Prospecção','2026-03-31', 10),
    ('OP4.2.2','operacional','Finalizar reportagem com a TV UFMG até Q1',                                                 'Parcerias','2026-03-31', 20),
    ('OP4.2.3','operacional','Obter ≥ 1 matéria espontânea em 2026',                                                      'Prospecção','2026-12-31', 30),
    ('OP5.1.1','operacional','Mapear ≥ 20 editais estratégicos até Q1',                                                   'Prospecção','2026-03-31', 10),
    ('OP5.1.2','operacional','Criar banco interno de templates (projeto, orçamento, cronograma, impacto) até Q1',         'Gestão','2026-03-31', 20),
    ('OP5.1.3','operacional','Definir pipeline trimestral de submissões até Q1',                                          'Prospecção','2026-03-31', 30),
    ('OP5.1.4','operacional','Submeter ≥ 6 propostas formais até Q4',                                                     'Prospecção','2026-12-31', 40),
    ('OP5.2.1','operacional','Mapear 30 potenciais parceiros estratégicos (hospitais, empresas, centros de pesquisa) até Q1','Parcerias','2026-03-31', 10),
    ('OP5.2.2','operacional','Realizar ≥ 15 reuniões institucionais até Q3',                                              'Parcerias','2026-09-30', 20),
    ('OP5.2.3','operacional','Formalizar ≥ 5 parcerias relevantes (acordo, carta de intenção ou convênio) até Q4',        'Parcerias','2026-12-31', 30),
    ('OP6.1.1','operacional','Definir formato e passo a passo do evento em Q1',                                           'Prospecção','2026-03-31', 10),
    ('OP6.1.2','operacional','Realizar evento anual até Q4 (≥ 150 participantes)',                                        'Prospecção','2026-12-31', 20),
    ('OP6.1.3','operacional','Participar da feira hospitalar até Q2',                                                     'Parcerias','2026-06-30', 30),
    ('OP6.1.4','operacional','Participar da CBEB até Q3',                                                                 'Científico','2026-09-30', 40),
    ('OP6.2.1','operacional','Criar trilhas completas de formação (hardware, IA, BCI, gestão, firmware) até Q4',          'Formação','2026-12-31', 10),
    ('OP6.2.2','operacional','Aumentar os setores de marketing, parcerias e gestão de pessoas',                           'Formação','2026-12-31', 20),
    ('OP6.2.3','operacional','Expandir rede de usuários/pacientes com ≥ 2 novos cadeirantes voluntários',                 'Formação','2026-12-31', 10)
  on conflict (codigo) do nothing;

  -- Vínculos pai -> filho (seguem a planilha; note que OP1.5.3
  -- desdobra OT1.6 e OP6.2.3 desdobra OT6.3, como no original)
  with vinculos(filho, pai) as (values
    ('OT1.1','OE1'), ('OT1.2','OE1'), ('OT1.3','OE1'), ('OT1.4','OE1'), ('OT1.5','OE1'), ('OT1.6','OE1'),
    ('OT2.1','OE2'), ('OT2.2','OE2'), ('OT2.3','OE2'),
    ('OT3.1','OE3'),
    ('OT4.1','OE4'), ('OT4.2','OE4'),
    ('OT5.1','OE5'), ('OT5.2','OE5'),
    ('OT6.1','OE6'), ('OT6.2','OE6'), ('OT6.3','OE6'),
    ('OP1.1.1','OT1.1'), ('OP1.1.2','OT1.1'), ('OP1.1.3','OT1.1'),
    ('OP1.2.1','OT1.2'), ('OP1.2.2','OT1.2'), ('OP1.2.3','OT1.2'), ('OP1.2.4','OT1.2'),
    ('OP1.3.1','OT1.3'), ('OP1.3.2','OT1.3'),
    ('OP1.4.1','OT1.4'),
    ('OP1.5.1','OT1.5'), ('OP1.5.2','OT1.5'),
    ('OP1.5.3','OT1.6'),
    ('OP2.1.1','OT2.1'),
    ('OP2.2.1','OT2.2'), ('OP2.2.2','OT2.2'), ('OP2.2.3','OT2.2'), ('OP2.2.4','OT2.2'),
    ('OP2.3.1','OT2.3'), ('OP2.3.2','OT2.3'), ('OP2.3.3','OT2.3'),
    ('OP3.1.1','OT3.1'), ('OP3.1.2','OT3.1'), ('OP3.1.3','OT3.1'),
    ('OP4.1.1','OT4.1'), ('OP4.1.2','OT4.1'),
    ('OP4.2.1','OT4.2'), ('OP4.2.2','OT4.2'), ('OP4.2.3','OT4.2'),
    ('OP5.1.1','OT5.1'), ('OP5.1.2','OT5.1'), ('OP5.1.3','OT5.1'), ('OP5.1.4','OT5.1'),
    ('OP5.2.1','OT5.2'), ('OP5.2.2','OT5.2'), ('OP5.2.3','OT5.2'),
    ('OP6.1.1','OT6.1'), ('OP6.1.2','OT6.1'), ('OP6.1.3','OT6.1'), ('OP6.1.4','OT6.1'),
    ('OP6.2.1','OT6.2'), ('OP6.2.2','OT6.2'),
    ('OP6.2.3','OT6.3'))
  update public.okr_objetivos f
     set pai_id = p.id
    from vinculos v
    join public.okr_objetivos p on p.codigo = v.pai
   where f.codigo = v.filho
     and f.pai_id is null;

  -- Prazo dos níveis tático e estratégico: o mais distante entre
  -- os desdobramentos (duas passadas: operacional -> tático -> estratégico)
  for i in 1..2 loop
    update public.okr_objetivos p
       set prazo = c.mx
      from (select pai_id, max(prazo) as mx
              from public.okr_objetivos
             where pai_id is not null and prazo is not null
             group by pai_id) c
     where c.pai_id = p.id
       and p.prazo is null;
  end loop;
end $$;

-- ============================================================
-- FIM — SOMA 8.0
-- Depois desta migração:
--   1) publique o index.html atualizado (aba "OKRs" na barra
--      lateral, visível para todos os papéis);
--   2) defina os responsáveis de cada objetivo pela própria
--      ferramenta (Detalhes -> Editar).
-- ============================================================
