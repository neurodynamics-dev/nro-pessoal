-- ============================================================
-- SOMA 6.0 — MIGRAÇÃO · NeuroDynamics
-- Módulo do PROCESSO SELETIVO: edições, cronograma público,
-- inscrições sem login (site selecao.neurodynamics.dev),
-- agendamento de dinâmicas e entrevistas, avaliação guiada
-- pelo comitê, publicações de resultados e integração do
-- candidato aprovado como membro (portabilidade total).
--
-- Pré-requisito: SOMA 5.0 aplicada.
-- Idempotente: pode rodar mais de uma vez sem duplicar nada.
-- COMO USAR: cole o arquivo INTEIRO no SQL Editor e Run.
-- ============================================================

-- ------------------------------------------------------------
-- 1. EDIÇÕES DO PROCESSO SELETIVO
--    O site público exibe a edição "publicada" mais recente.
--    "rascunho" fica invisível ao público; "encerrada" sai do ar.
-- ------------------------------------------------------------
create table if not exists public.ps_edicoes (
  id                 uuid primary key default gen_random_uuid(),
  nome               text not null,
  slug               text not null unique,
  descricao          text,
  edital_url         text,
  status             text not null default 'rascunho'
                     check (status in ('rascunho','publicada','encerrada')),
  inscricoes_inicio  date not null,
  inscricoes_fim     date not null,
  areas              text[] not null default '{}',   -- áreas de interesse exibidas no formulário
  criado_em          timestamptz not null default now(),
  constraint ps_ed_periodo check (inscricoes_fim >= inscricoes_inicio)
);

-- ------------------------------------------------------------
-- 2. CRONOGRAMA (etapas exibidas na linha do tempo do site)
--    "fase" só classifica o marco para cor/ícone no site.
-- ------------------------------------------------------------
create table if not exists public.ps_etapas (
  id          uuid primary key default gen_random_uuid(),
  edicao_id   uuid not null references public.ps_edicoes(id) on delete cascade,
  ordem       integer not null default 100,
  titulo      text not null,
  data_inicio date not null,
  data_fim    date,
  fase        text not null default 'outro'
              check (fase in ('divulgacao','inscricao','dinamica','entrevista','trainee','resultado','outro')),
  descricao   text
);
create index if not exists idx_psetapas_edicao on public.ps_etapas (edicao_id, ordem);

-- ------------------------------------------------------------
-- 3. CANDIDATOS
--    Sem login: o candidato se identifica no site apenas com
--    protocolo + e-mail. Os campos espelham dados_pessoais para
--    garantir portabilidade total na integração como membro.
--    O status carrega o funil inteiro do processo.
-- ------------------------------------------------------------
create table if not exists public.ps_candidatos (
  id                    uuid primary key default gen_random_uuid(),
  edicao_id             uuid not null references public.ps_edicoes(id) on delete cascade,
  numero                integer generated always as identity,
  protocolo             text unique,
  status                text not null default 'inscrito'
                        check (status in ('inscrito','indeferido','deferido',
                                          'reprovado_dinamica','aprovado_dinamica',
                                          'reprovado_entrevista','aprovado_entrevista',
                                          'trainee','reprovado_final','aprovado_final',
                                          'integrado','desistente')),
  -- dados pessoais
  nome                  text not null,
  email                 text not null,
  telefone              text,
  data_nascimento       date,
  cidade_origem         text,
  genero                text,
  autodeclaracao_racial text,
  acessibilidade        text,
  -- dados acadêmicos
  instituicao           text,
  curso                 text,
  matricula             text,
  periodo               text,
  background            text,
  lattes                text,
  github                text,
  linkedin              text,
  instagram             text,
  portfolio             text,
  -- sobre o processo
  areas_interesse       text[] not null default '{}',
  motivacao             text,
  disponibilidade       text,
  como_soube            text,
  -- consentimentos
  aceite_edital         boolean not null default false,
  aceite_lgpd           boolean not null default false,
  autorizacao_imagem    boolean not null default false,
  -- integração (preenchido quando vira membro)
  registro_membro       integer references public.membros(registro) on delete set null,
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now()
);
create unique index if not exists ux_pscand_email
  on public.ps_candidatos (edicao_id, lower(email));
create index if not exists idx_pscand_status on public.ps_candidatos (edicao_id, status);

drop trigger if exists tg_upd_pscand on public.ps_candidatos;
create trigger tg_upd_pscand before update on public.ps_candidatos
  for each row execute function public.fn_atualizado();

-- ------------------------------------------------------------
-- 4. AVALIAÇÕES DO COMITÊ (a "trilha" que o SOMA guia)
--    Uma avaliação por avaliador × candidato × fase. Os critérios
--    de cada fase são definidos na ferramenta (soma-selecao.html)
--    e gravados em jsonb: {"Comunicação": 4, "Proatividade": 5}.
-- ------------------------------------------------------------
create table if not exists public.ps_avaliacoes (
  id           uuid primary key default gen_random_uuid(),
  candidato_id uuid not null references public.ps_candidatos(id) on delete cascade,
  fase         text not null
               check (fase in ('dinamica','entrevista','desafio',
                               'parcial_1','parcial_2','apresentacao_final')),
  criterios    jsonb not null default '{}'::jsonb,
  nota         numeric(4,2),
  parecer      text,
  recomendacao text check (recomendacao in ('aprovar','reprovar','em_duvida')),
  avaliador_id uuid not null default auth.uid(),
  avaliador    text,
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (candidato_id, fase, avaliador_id)
);
create index if not exists idx_psaval_cand on public.ps_avaliacoes (candidato_id, fase);

drop trigger if exists tg_upd_psaval on public.ps_avaliacoes;
create trigger tg_upd_psaval before update on public.ps_avaliacoes
  for each row execute function public.fn_atualizado();

-- ------------------------------------------------------------
-- 5. AGENDA (estilo Calendly): o comitê abre janelas de horário
--    (slots) para dinâmicas e entrevistas; o candidato escolhe
--    uma no site. "capacidade" > 1 permite dinâmicas em grupo.
-- ------------------------------------------------------------
create table if not exists public.ps_slots (
  id          uuid primary key default gen_random_uuid(),
  edicao_id   uuid not null references public.ps_edicoes(id) on delete cascade,
  fase        text not null check (fase in ('dinamica','entrevista')),
  data        date not null,
  hora_inicio time not null,
  hora_fim    time not null,
  local       text,
  capacidade  integer not null default 1 check (capacidade > 0),
  ativo       boolean not null default true,
  criado_em   timestamptz not null default now(),
  constraint ps_slot_horario check (hora_fim > hora_inicio)
);
create index if not exists idx_psslots_edicao on public.ps_slots (edicao_id, fase, data);

create table if not exists public.ps_agendamentos (
  id           uuid primary key default gen_random_uuid(),
  slot_id      uuid not null references public.ps_slots(id) on delete cascade,
  candidato_id uuid not null references public.ps_candidatos(id) on delete cascade,
  fase         text not null check (fase in ('dinamica','entrevista')),
  compareceu   boolean,
  criado_em    timestamptz not null default now(),
  unique (candidato_id, fase)          -- um horário por fase; reagendar substitui
);
create index if not exists idx_psag_slot on public.ps_agendamentos (slot_id);

-- ------------------------------------------------------------
-- 6. PUBLICAÇÕES (edital, avisos e resultados)
--    Só o que estiver "publicado" aparece no site — e os status
--    dos candidatos só ficam visíveis ao próprio candidato
--    DEPOIS que a publicação da etapa correspondente sai.
--    As listas de aprovados são geradas na hora, a partir do
--    status atual dos candidatos.
-- ------------------------------------------------------------
create table if not exists public.ps_publicacoes (
  id           uuid primary key default gen_random_uuid(),
  edicao_id    uuid not null references public.ps_edicoes(id) on delete cascade,
  tipo         text not null
               check (tipo in ('edital','aviso','deferimento',
                               'resultado_dinamica','resultado_entrevista','resultado_final')),
  titulo       text not null,
  corpo        text,
  url_anexo    text,
  publicado    boolean not null default false,
  publicado_em timestamptz,
  criado_por   text,
  criado_em    timestamptz not null default now()
);
create index if not exists idx_pspub_edicao on public.ps_publicacoes (edicao_id, publicado);

-- ------------------------------------------------------------
-- 7. COMITÊ DE SELEÇÃO
--    Membros indicados aqui ganham acesso total ao módulo na
--    ferramenta soma-selecao.html, mesmo com papel "leitura".
--    admin/pessoal sempre têm acesso.
-- ------------------------------------------------------------
create table if not exists public.ps_comite (
  edicao_id uuid not null references public.ps_edicoes(id) on delete cascade,
  registro  integer not null references public.membros(registro) on delete cascade,
  primary key (edicao_id, registro)
);

create or replace function public.eh_comite()
returns boolean language sql stable security definer
set search_path = public
as $$
  select public.papel_atual() in ('admin','pessoal')
      or exists (select 1
                   from public.ps_comite c
                   join public.perfis p on p.registro = c.registro
                  where p.id = auth.uid());
$$;
grant execute on function public.eh_comite() to authenticated;

-- ------------------------------------------------------------
-- 8. AUDITORIA (mesmo gatilho das demais tabelas do sistema)
-- ------------------------------------------------------------
drop trigger if exists tg_aud_psedicoes on public.ps_edicoes;
create trigger tg_aud_psedicoes after insert or update or delete on public.ps_edicoes
  for each row execute function public.fn_auditoria();
drop trigger if exists tg_aud_psetapas on public.ps_etapas;
create trigger tg_aud_psetapas after insert or update or delete on public.ps_etapas
  for each row execute function public.fn_auditoria();
drop trigger if exists tg_aud_pscand on public.ps_candidatos;
create trigger tg_aud_pscand after insert or update or delete on public.ps_candidatos
  for each row execute function public.fn_auditoria();
drop trigger if exists tg_aud_psaval on public.ps_avaliacoes;
create trigger tg_aud_psaval after insert or update or delete on public.ps_avaliacoes
  for each row execute function public.fn_auditoria();
drop trigger if exists tg_aud_psslots on public.ps_slots;
create trigger tg_aud_psslots after insert or update or delete on public.ps_slots
  for each row execute function public.fn_auditoria();
drop trigger if exists tg_aud_psag on public.ps_agendamentos;
create trigger tg_aud_psag after insert or update or delete on public.ps_agendamentos
  for each row execute function public.fn_auditoria();
drop trigger if exists tg_aud_pspub on public.ps_publicacoes;
create trigger tg_aud_pspub after insert or update or delete on public.ps_publicacoes
  for each row execute function public.fn_auditoria();

-- ------------------------------------------------------------
-- 9. SEGURANÇA (RLS)
--    Nenhuma tabela do módulo tem política para "anon": o site
--    público só conversa com o banco pelas funções da seção 10.
--    Autenticados: apenas o comitê (e admin/pessoal) leem e
--    escrevem — dados de candidato são sensíveis (LGPD).
-- ------------------------------------------------------------
alter table public.ps_edicoes      enable row level security;
alter table public.ps_etapas       enable row level security;
alter table public.ps_candidatos   enable row level security;
alter table public.ps_avaliacoes   enable row level security;
alter table public.ps_slots        enable row level security;
alter table public.ps_agendamentos enable row level security;
alter table public.ps_publicacoes  enable row level security;
alter table public.ps_comite       enable row level security;

do $$
declare t text;
begin
  foreach t in array array['ps_edicoes','ps_etapas','ps_candidatos','ps_avaliacoes',
                           'ps_slots','ps_agendamentos','ps_publicacoes'] loop
    execute format('drop policy if exists %I_comite on public.%I', t, t);
    execute format('create policy %I_comite on public.%I for all to authenticated
                    using (public.eh_comite()) with check (public.eh_comite())', t, t);
  end loop;
end $$;

-- comitê: qualquer autenticado consulta (a ferramenta precisa saber
-- quem participa); só admin/pessoal alteram a composição
drop policy if exists pscom_select on public.ps_comite;
create policy pscom_select on public.ps_comite for select to authenticated using (true);
drop policy if exists pscom_write on public.ps_comite;
create policy pscom_write on public.ps_comite for all to authenticated
  using (public.papel_atual() in ('admin','pessoal'))
  with check (public.papel_atual() in ('admin','pessoal'));

-- ------------------------------------------------------------
-- 10. FUNÇÕES PÚBLICAS (chamadas pelo site com a chave anon)
-- ------------------------------------------------------------

-- 10a. Estado público do processo: edição, cronograma e
--      publicações (com listas de aprovados geradas na hora).
create or replace function public.ps_site()
returns jsonb language plpgsql stable security definer
set search_path = public
as $$
declare
  v_ed   public.ps_edicoes%rowtype;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  select * into v_ed from ps_edicoes
   where status = 'publicada'
   order by criado_em desc limit 1;
  if not found then return null; end if;

  return jsonb_build_object(
    'edicao', jsonb_build_object(
      'nome', v_ed.nome, 'slug', v_ed.slug, 'descricao', v_ed.descricao,
      'edital_url', v_ed.edital_url,
      'inscricoes_inicio', v_ed.inscricoes_inicio,
      'inscricoes_fim', v_ed.inscricoes_fim,
      'inscricoes_abertas', v_hoje between v_ed.inscricoes_inicio and v_ed.inscricoes_fim,
      'areas', to_jsonb(v_ed.areas)
    ),
    'hoje', v_hoje,
    'etapas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'titulo', e.titulo, 'data_inicio', e.data_inicio, 'data_fim', e.data_fim,
        'fase', e.fase, 'descricao', e.descricao
      ) order by e.ordem, e.data_inicio)
      from ps_etapas e where e.edicao_id = v_ed.id
    ), '[]'::jsonb),
    'publicacoes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'tipo', p.tipo, 'titulo', p.titulo, 'corpo', p.corpo,
        'url_anexo', p.url_anexo, 'publicado_em', p.publicado_em,
        'resultados', case when p.tipo in ('deferimento','resultado_dinamica',
                                           'resultado_entrevista','resultado_final')
          then coalesce((
            select jsonb_agg(jsonb_build_object('protocolo', c.protocolo, 'nome', c.nome)
                             order by c.nome)
            from ps_candidatos c
            where c.edicao_id = v_ed.id and c.status = any(
              case p.tipo
                when 'deferimento' then array['deferido','reprovado_dinamica','aprovado_dinamica',
                  'reprovado_entrevista','aprovado_entrevista','trainee','reprovado_final',
                  'aprovado_final','integrado']
                when 'resultado_dinamica' then array['aprovado_dinamica','reprovado_entrevista',
                  'aprovado_entrevista','trainee','reprovado_final','aprovado_final','integrado']
                when 'resultado_entrevista' then array['aprovado_entrevista','trainee',
                  'reprovado_final','aprovado_final','integrado']
                else array['aprovado_final','integrado']
              end)
          ), '[]'::jsonb)
          else null end
      ) order by p.publicado_em desc)
      from ps_publicacoes p
      where p.edicao_id = v_ed.id and p.publicado
    ), '[]'::jsonb)
  );
end $$;
grant execute on function public.ps_site() to anon, authenticated;

-- 10b. Inscrição (única escrita anônima em ps_candidatos).
--      Valida o período, impede duplicidade por e-mail e devolve
--      o protocolo — a "chave" do candidato para acompanhar tudo.
create or replace function public.ps_inscrever(p jsonb)
returns jsonb language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_ed    public.ps_edicoes%rowtype;
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
  v_email text := lower(trim(coalesce(p->>'email','')));
  v_nome  text := trim(coalesce(p->>'nome',''));
  v_id    uuid;
  v_num   integer;
  v_prot  text;
begin
  select * into v_ed from ps_edicoes
   where status = 'publicada' order by criado_em desc limit 1;
  if not found then
    return jsonb_build_object('status','sem_edicao');
  end if;
  if v_hoje < v_ed.inscricoes_inicio or v_hoje > v_ed.inscricoes_fim then
    return jsonb_build_object('status','fora_do_periodo');
  end if;
  if length(v_nome) < 5 or position(' ' in v_nome) = 0 then
    return jsonb_build_object('status','invalido','campo','nome');
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('status','invalido','campo','email');
  end if;
  if coalesce((p->>'aceite_lgpd')::boolean, false) is not true
     or coalesce((p->>'aceite_edital')::boolean, false) is not true then
    return jsonb_build_object('status','invalido','campo','aceites');
  end if;
  if exists (select 1 from ps_candidatos
              where edicao_id = v_ed.id and lower(email) = v_email) then
    return jsonb_build_object('status','duplicado');
  end if;

  insert into ps_candidatos (edicao_id, nome, email, telefone, data_nascimento,
    cidade_origem, genero, autodeclaracao_racial, acessibilidade,
    instituicao, curso, matricula, periodo, background,
    lattes, github, linkedin, instagram, portfolio,
    areas_interesse, motivacao, disponibilidade, como_soube,
    aceite_edital, aceite_lgpd, autorizacao_imagem)
  values (v_ed.id, left(v_nome,160), v_email, left(p->>'telefone',40),
    nullif(p->>'data_nascimento','')::date,
    left(p->>'cidade_origem',120), left(p->>'genero',60),
    left(p->>'autodeclaracao_racial',40), left(p->>'acessibilidade',400),
    left(p->>'instituicao',160), left(p->>'curso',120), left(p->>'matricula',40),
    left(p->>'periodo',30), left(p->>'background',4000),
    left(p->>'lattes',300), left(p->>'github',300), left(p->>'linkedin',300),
    left(p->>'instagram',120), left(p->>'portfolio',300),
    coalesce((select array_agg(left(x,80)) from jsonb_array_elements_text(
      case when jsonb_typeof(p->'areas_interesse')='array'
           then p->'areas_interesse' else '[]'::jsonb end) x), '{}'),
    left(p->>'motivacao',4000), left(p->>'disponibilidade',60), left(p->>'como_soube',120),
    true, true, coalesce((p->>'autorizacao_imagem')::boolean, false))
  returning id, numero into v_id, v_num;

  v_prot := 'PS' || to_char(v_hoje,'YY') || '-' || lpad(v_num::text, 4, '0');
  update ps_candidatos set protocolo = v_prot where id = v_id;

  return jsonb_build_object('status','ok','protocolo',v_prot);
end $$;
grant execute on function public.ps_inscrever(jsonb) to anon, authenticated;

-- 10c. (interna) Localiza o candidato por protocolo + e-mail e
--      calcula o status VISÍVEL: resultados só aparecem depois
--      que a publicação da etapa correspondente for publicada.
create or replace function public._ps_candidato(p_protocolo text, p_email text)
returns table (cand public.ps_candidatos, status_visivel text, fase_agendavel text)
language plpgsql stable security definer
set search_path = public
as $$
declare
  c        public.ps_candidatos%rowtype;
  pub_def  boolean; pub_d1 boolean; pub_d2 boolean; pub_fin boolean;
  v_st     text;
begin
  select * into c from ps_candidatos
   where upper(trim(protocolo)) = upper(trim(p_protocolo))
     and lower(email) = lower(trim(p_email));
  if not found then return; end if;

  select bool_or(tipo='deferimento'), bool_or(tipo='resultado_dinamica'),
         bool_or(tipo='resultado_entrevista'), bool_or(tipo='resultado_final')
    into pub_def, pub_d1, pub_d2, pub_fin
    from ps_publicacoes where edicao_id = c.edicao_id and publicado;
  pub_def := coalesce(pub_def,false); pub_d1 := coalesce(pub_d1,false);
  pub_d2  := coalesce(pub_d2,false);  pub_fin := coalesce(pub_fin,false);

  v_st := case
    when c.status in ('inscrito','desistente','trainee') then c.status
    when c.status in ('deferido','indeferido') then
      case when pub_def then c.status else 'inscrito' end
    when c.status in ('aprovado_dinamica','reprovado_dinamica') then
      case when pub_d1 then c.status when pub_def then 'deferido' else 'inscrito' end
    when c.status in ('aprovado_entrevista','reprovado_entrevista') then
      case when pub_d2 then c.status when pub_d1 then 'aprovado_dinamica'
           when pub_def then 'deferido' else 'inscrito' end
    when c.status in ('aprovado_final','reprovado_final') then
      case when pub_fin then c.status else 'trainee' end
    when c.status = 'integrado' then
      case when pub_fin then 'integrado' else 'trainee' end
    else c.status end;

  cand := c; status_visivel := v_st;
  fase_agendavel := case v_st when 'deferido' then 'dinamica'
                              when 'aprovado_dinamica' then 'entrevista'
                              else null end;
  return next;
end $$;
revoke all on function public._ps_candidato(text, text) from public, anon, authenticated;

-- 10d. Acompanhamento: situação do candidato + agendamentos.
create or replace function public.ps_acompanhar(p_protocolo text, p_email text)
returns jsonb language plpgsql stable security definer
set search_path = public
as $$
declare r record;
begin
  select * into r from public._ps_candidato(p_protocolo, p_email);
  if not found then return jsonb_build_object('status','nao_encontrado'); end if;

  return jsonb_build_object(
    'status','ok',
    'nome', (r.cand).nome,
    'protocolo', (r.cand).protocolo,
    'situacao', r.status_visivel,
    'fase_agendavel', r.fase_agendavel,
    'agendamentos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'fase', a.fase, 'data', s.data,
        'hora_inicio', to_char(s.hora_inicio,'HH24:MI'),
        'hora_fim', to_char(s.hora_fim,'HH24:MI'), 'local', s.local
      ) order by s.data)
      from ps_agendamentos a join ps_slots s on s.id = a.slot_id
      where a.candidato_id = (r.cand).id
    ), '[]'::jsonb)
  );
end $$;
grant execute on function public.ps_acompanhar(text, text) to anon, authenticated;

-- 10e. Horários disponíveis para a fase agendável do candidato.
create or replace function public.ps_horarios(p_protocolo text, p_email text)
returns jsonb language plpgsql stable security definer
set search_path = public
as $$
declare
  r record;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  select * into r from public._ps_candidato(p_protocolo, p_email);
  if not found then return jsonb_build_object('status','nao_encontrado'); end if;
  if r.fase_agendavel is null then
    return jsonb_build_object('status','sem_fase');
  end if;

  return jsonb_build_object(
    'status','ok', 'fase', r.fase_agendavel,
    'slots', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'data', s.data,
        'hora_inicio', to_char(s.hora_inicio,'HH24:MI'),
        'hora_fim', to_char(s.hora_fim,'HH24:MI'),
        'local', s.local,
        'vagas', s.capacidade - (select count(*) from ps_agendamentos a
                                  where a.slot_id = s.id
                                    and a.candidato_id <> (r.cand).id),
        'meu', exists (select 1 from ps_agendamentos a
                        where a.slot_id = s.id and a.candidato_id = (r.cand).id)
      ) order by s.data, s.hora_inicio)
      from ps_slots s
      where s.edicao_id = (r.cand).edicao_id
        and s.fase = r.fase_agendavel and s.ativo
        and s.data >= v_hoje
    ), '[]'::jsonb)
  );
end $$;
grant execute on function public.ps_horarios(text, text) to anon, authenticated;

-- 10f. Agendar (ou reagendar): valida fase, capacidade e data.
--      O "for update" no slot serializa reservas concorrentes.
create or replace function public.ps_agendar(p_protocolo text, p_email text, p_slot uuid)
returns jsonb language plpgsql volatile security definer
set search_path = public
as $$
declare
  r      record;
  v_slot public.ps_slots%rowtype;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ocup integer;
begin
  select * into r from public._ps_candidato(p_protocolo, p_email);
  if not found then return jsonb_build_object('status','nao_encontrado'); end if;
  if r.fase_agendavel is null then
    return jsonb_build_object('status','sem_fase');
  end if;

  select * into v_slot from ps_slots where id = p_slot for update;
  if not found or not v_slot.ativo or v_slot.fase <> r.fase_agendavel
     or v_slot.edicao_id <> (r.cand).edicao_id or v_slot.data < v_hoje then
    return jsonb_build_object('status','indisponivel');
  end if;

  select count(*) into v_ocup from ps_agendamentos
   where slot_id = p_slot and candidato_id <> (r.cand).id;
  if v_ocup >= v_slot.capacidade then
    return jsonb_build_object('status','lotado');
  end if;

  delete from ps_agendamentos
   where candidato_id = (r.cand).id and fase = r.fase_agendavel;
  insert into ps_agendamentos (slot_id, candidato_id, fase)
  values (p_slot, (r.cand).id, r.fase_agendavel);

  return jsonb_build_object('status','ok',
    'data', v_slot.data,
    'hora_inicio', to_char(v_slot.hora_inicio,'HH24:MI'),
    'hora_fim', to_char(v_slot.hora_fim,'HH24:MI'),
    'local', v_slot.local);
end $$;
grant execute on function public.ps_agendar(text, text, uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 11. INTEGRAÇÃO CANDIDATO → MEMBRO (portabilidade total)
--     Chamada pela ferramenta do comitê ao final do trainee.
--     Cria membros + dados_pessoais a partir da ficha do
--     candidato e registra a ocorrência de ingresso.
-- ------------------------------------------------------------
create or replace function public.ps_integrar(p_candidato uuid, p_registro integer,
                                              p_departamento text default null,
                                              p_cargo text default null)
returns jsonb language plpgsql volatile security definer
set search_path = public
as $$
declare
  c    public.ps_candidatos%rowtype;
  v_ed public.ps_edicoes%rowtype;
  v_resp text;
begin
  if not public.eh_comite() then
    raise exception 'acesso restrito ao comitê de seleção';
  end if;

  select * into c from ps_candidatos where id = p_candidato;
  if not found then return jsonb_build_object('status','nao_encontrado'); end if;
  if c.status not in ('trainee','aprovado_final') then
    return jsonb_build_object('status','status_invalido','atual',c.status);
  end if;
  if exists (select 1 from membros where registro = p_registro) then
    return jsonb_build_object('status','registro_em_uso');
  end if;

  select * into v_ed from ps_edicoes where id = c.edicao_id;
  select coalesce(nome, email) into v_resp from perfis where id = auth.uid();

  insert into membros (registro, status, nome, departamento, cargo,
                       email_pessoal, telefone, data_ingresso, forma_ingresso)
  values (p_registro, 'Ativo', c.nome, p_departamento, p_cargo,
          c.email, c.telefone,
          (now() at time zone 'America/Sao_Paulo')::date,
          'Processo Seletivo');

  insert into dados_pessoais (registro, data_nascimento, cidade_origem,
    instituicao, curso, matricula, periodo_ingresso, background, lattes,
    github, instagram, genero, autodeclaracao_racial, acessibilidade,
    autorizacao_imagem)
  values (p_registro, c.data_nascimento, c.cidade_origem,
    c.instituicao, c.curso, c.matricula, c.periodo, c.background, c.lattes,
    c.github, c.instagram, c.genero, c.autodeclaracao_racial, c.acessibilidade,
    c.autorizacao_imagem)
  on conflict (registro) do nothing;

  insert into ocorrencias (registro, tipo, descricao, responsavel)
  values (p_registro, 'Ingresso',
          'Aprovado(a) no ' || v_ed.nome || ' (protocolo ' || coalesce(c.protocolo,'—') || ').',
          v_resp);

  update ps_candidatos
     set status = 'integrado', registro_membro = p_registro
   where id = p_candidato;

  return jsonb_build_object('status','ok','registro',p_registro);
end $$;
grant execute on function public.ps_integrar(uuid, integer, text, text) to authenticated;

-- ------------------------------------------------------------
-- 12. DADOS INICIAIS — Processo Seletivo 2026 com o cronograma
--     oficial. Criado como "publicada" para o site já nascer
--     com conteúdo; ajuste datas e textos em soma-selecao.html.
-- ------------------------------------------------------------
do $$
declare v_id uuid;
begin
  if exists (select 1 from public.ps_edicoes where slug = 'ps-2026') then return; end if;

  insert into public.ps_edicoes (nome, slug, descricao, status,
                                 inscricoes_inicio, inscricoes_fim, areas)
  values ('Processo Seletivo 2026', 'ps-2026',
          'A NeuroDynamics abre as portas para novos talentos. Um processo em três fases — dinâmicas em grupo, entrevistas individuais e período trainee — para quem quer construir tecnologia de ponta com a gente.',
          'publicada', date '2026-08-03', date '2026-08-23',
          '{Mecânica,Eletrônica,Software,Simulação,Gestão e Operações,Comunicação e Marketing}')
  returning id into v_id;

  insert into public.ps_etapas (edicao_id, ordem, titulo, data_inicio, data_fim, fase) values
    (v_id, 10,  'Divulgação do edital',                        date '2026-07-17', null,              'divulgacao'),
    (v_id, 20,  'Inscrições',                                  date '2026-08-03', date '2026-08-23', 'inscricao'),
    (v_id, 30,  'Divulgação das inscrições deferidas',         date '2026-08-24', null,              'resultado'),
    (v_id, 40,  'Realização das dinâmicas em grupo',           date '2026-08-26', date '2026-08-29', 'dinamica'),
    (v_id, 50,  'Divulgação do resultado da primeira etapa',   date '2026-08-31', null,              'resultado'),
    (v_id, 60,  'Realização das entrevistas individuais',      date '2026-09-01', date '2026-09-05', 'entrevista'),
    (v_id, 70,  'Divulgação do resultado da segunda etapa',    date '2026-09-08', null,              'resultado'),
    (v_id, 80,  'Início do período trainee',                   date '2026-09-09', null,              'trainee'),
    (v_id, 90,  'Divulgação do Desafio trainee',               date '2026-09-14', null,              'trainee'),
    (v_id, 100, 'Reunião geral e integração com novos trainees', date '2026-09-19', null,            'trainee'),
    (v_id, 110, 'Primeira avaliação parcial',                  date '2026-10-01', date '2026-10-03', 'trainee'),
    (v_id, 120, 'Segunda avaliação parcial',                   date '2026-11-14', null,              'trainee'),
    (v_id, 130, 'Apresentação final',                          date '2026-11-28', null,              'trainee'),
    (v_id, 140, 'Divulgação do resultado final',               date '2026-11-30', null,              'resultado');
end $$;

-- ============================================================
-- FIM — SOMA 6.0
-- Depois desta migração:
--   1) publique soma-selecao.html junto dos demais arquivos do
--      SOMA (pessoal.neurodynamics.dev/soma-selecao.html);
--   2) publique a pasta selecao/ em selecao.neurodynamics.dev
--      (veja selecao/README.md);
--   3) indique o comitê de seleção na aba Configurações da
--      ferramenta (admin/pessoal já entram sem indicação);
--   4) cadastre o edital em Publicações e publique-o.
-- ============================================================
