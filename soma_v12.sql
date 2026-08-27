-- ============================================================
-- SOMA 12.0 — MIGRAÇÃO · NeuroDynamics
-- DINÂMICA EM GRUPO do processo seletivo: conteúdo do roteiro
-- e do painel de projeção editáveis pelo SOMA, código de sala
-- por janela, grupos, registro do desafio pelo celular do
-- candidato e avaliação ao vivo — tudo com janela de tempo.
--
-- As três páginas do site (selecao.neurodynamics.dev):
--   dinamica.html            candidato registra o desafio
--   dinamica-painel.html     painel projetado na sala
--   dinamica-avaliador.html  mesa do avaliador (login + janela)
--
-- Pré-requisito: soma_v6.sql aplicada (módulo do PS).
-- Idempotente: pode rodar mais de uma vez sem duplicar nada.
-- COMO USAR: cole o arquivo INTEIRO no SQL Editor e Run.
-- ============================================================

-- ------------------------------------------------------------
-- 1. CÓDIGO DA SALA, NA PRÓPRIA JANELA
--    Cada slot de dinâmica ganha um código curto de 4 letras.
--    É ele que o candidato digita no celular e que aparece no
--    QR do painel. Alfabeto sem O/0/I/1/S/5 — o código é lido
--    de longe, num projetor, por gente com pressa.
-- ------------------------------------------------------------
alter table public.ps_slots add column if not exists codigo text;
create unique index if not exists ux_psslots_codigo
  on public.ps_slots (codigo) where codigo is not null;

create or replace function public.fn_din_codigo()
returns text language plpgsql volatile
set search_path = public
as $$
declare
  alfabeto text := 'ABCDEFGHJKLMNPQRTUVWXYZ2346789';
  tentativa text;
  t integer;
  k integer;
begin
  for t in 1..200 loop
    tentativa := '';
    for k in 1..4 loop
      tentativa := tentativa || substr(alfabeto, 1 + floor(random()*length(alfabeto))::int, 1);
    end loop;
    if not exists (select 1 from ps_slots where codigo = tentativa) then
      return tentativa;
    end if;
  end loop;
  -- improvável: cai para um código de 6 letras
  return upper(substr(replace(gen_random_uuid()::text,'-',''), 1, 6));
end $$;

create or replace function public.fn_din_slot_codigo()
returns trigger language plpgsql
set search_path = public
as $$
begin
  if new.fase = 'dinamica' and new.codigo is null then
    new.codigo := public.fn_din_codigo();
  end if;
  return new;
end $$;

drop trigger if exists tg_din_slot_codigo on public.ps_slots;
create trigger tg_din_slot_codigo before insert on public.ps_slots
  for each row execute function public.fn_din_slot_codigo();

-- Janela criada antes desta migração ganha código sob demanda: o SOMA
-- chama esta função ao abrir a aba Dinâmica. Ficou fora de um UPDATE em
-- massa de propósito — não vale acordar o gatilho de auditoria de
-- ps_slots inteiro por causa de um código de quatro letras.
create or replace function public.ps_din_codigo_gerar(p_slot uuid)
returns jsonb language plpgsql volatile security definer
set search_path = public
as $$
declare v_cod text;
begin
  if not public.eh_comite() then return jsonb_build_object('status','sem_acesso'); end if;
  select codigo into v_cod from ps_slots where id = p_slot and fase = 'dinamica';
  if not found then return jsonb_build_object('status','nao_encontrada'); end if;
  if v_cod is null then
    v_cod := public.fn_din_codigo();
    update ps_slots set codigo = v_cod where id = p_slot;
  end if;
  return jsonb_build_object('status','ok','codigo',v_cod);
end $$;
grant execute on function public.ps_din_codigo_gerar(uuid) to authenticated;

-- ------------------------------------------------------------
-- 2. CONFIGURAÇÃO DA DINÂMICA (uma linha por edição)
--    Textos do painel e as duas tolerâncias que definem quando
--    as páginas abrem e fecham em volta do horário da janela.
-- ------------------------------------------------------------
create table if not exists public.ps_din_config (
  edicao_id         uuid primary key references public.ps_edicoes(id) on delete cascade,
  titulo            text not null default 'Dinâmica em grupo',
  subtitulo         text,
  resumo_equipe     text,
  desafio_titulo    text not null default 'Sprint da bancada',
  desafio_contexto  text,
  aviso_lgpd        text,
  wifi_rede         text,
  wifi_senha        text,
  minutos_total     integer not null default 75 check (minutos_total between 20 and 240),
  tam_grupo         integer not null default 5 check (tam_grupo between 2 and 8),
  tolerancia_antes  integer not null default 30 check (tolerancia_antes between 0 and 240),
  tolerancia_depois integer not null default 30 check (tolerancia_depois between 0 and 240),
  atualizado_em     timestamptz not null default now(),
  atualizado_por    text
);

-- ------------------------------------------------------------
-- 3. CONTEÚDO, EM UMA TABELA SÓ
--    Tudo que o comitê edita — cartões do painel, blocos do
--    roteiro, casos do desafio, campos do formulário, critérios
--    de avaliação e a apresentação dos avaliadores — mora aqui,
--    com o formato de cada tipo em "dados".
--
--    edicao_id nulo = vale para todas as edições.
--    slot_id  nulo = vale para todas as janelas da edição.
--
--    Formato de "dados" por tipo:
--      cartao    {titulo, texto}
--      bloco     {nome, minutos, fala[], projetor, corte}
--      caso      {titulo, pessoa, necessidade, restricoes[], pista}
--      campo     {chave, rotulo, ajuda, limite, linhas}
--      criterio  {nome, a1, a3, a5}
--      avaliador {nome, cargo, curso, foto_url, fala}   (use slot_id)
--      regra     {texto}
-- ------------------------------------------------------------
create table if not exists public.ps_din_itens (
  id        uuid primary key default gen_random_uuid(),
  edicao_id uuid references public.ps_edicoes(id) on delete cascade,
  slot_id   uuid references public.ps_slots(id) on delete cascade,
  tipo      text not null check (tipo in ('cartao','bloco','caso','campo','criterio','avaliador','regra')),
  ordem     integer not null default 100,
  ativo     boolean not null default true,
  dados     jsonb   not null default '{}'::jsonb,
  criado_em timestamptz not null default now()
);
create index if not exists idx_dinitens on public.ps_din_itens (tipo, edicao_id, ordem);
create index if not exists idx_dinitens_slot on public.ps_din_itens (slot_id) where slot_id is not null;

-- ------------------------------------------------------------
-- 4. GRUPOS DA JANELA
--    Formados na hora, pelo avaliador, com quem apareceu.
--    "membros" guarda os candidatos agendados que entraram no
--    grupo; "avulsos" guarda nome digitado de quem não estava
--    na lista (acontece, e a dinâmica não pode parar por isso).
-- ------------------------------------------------------------
create table if not exists public.ps_din_grupos (
  id        uuid primary key default gen_random_uuid(),
  slot_id   uuid not null references public.ps_slots(id) on delete cascade,
  letra     text not null,
  caso_id   uuid references public.ps_din_itens(id) on delete set null,
  membros   uuid[] not null default '{}',
  avulsos   text[] not null default '{}',
  criado_em timestamptz not null default now(),
  unique (slot_id, letra)
);
create index if not exists idx_dingrupos_slot on public.ps_din_grupos (slot_id);

-- ------------------------------------------------------------
-- 5. REGISTRO DO DESAFIO
--    Uma linha por grupo. "versao" sobe a cada gravação: é o
--    que permite avisar quando duas pessoas do mesmo grupo
--    editam ao mesmo tempo, em vez de uma apagar a outra.
-- ------------------------------------------------------------
create table if not exists public.ps_din_registros (
  grupo_id       uuid primary key references public.ps_din_grupos(id) on delete cascade,
  dados          jsonb not null default '{}'::jsonb,
  versao         integer not null default 0,
  atualizado_em  timestamptz not null default now(),
  atualizado_por text
);

-- ------------------------------------------------------------
-- 6. AUDITORIA E RLS
--    Nenhuma tabela tem política para "anon": o site conversa
--    com o banco só pelas funções da seção 8.
-- ------------------------------------------------------------
drop trigger if exists tg_aud_dinconfig on public.ps_din_config;
create trigger tg_aud_dinconfig after insert or update or delete on public.ps_din_config
  for each row execute function public.fn_auditoria();
drop trigger if exists tg_aud_dinitens on public.ps_din_itens;
create trigger tg_aud_dinitens after insert or update or delete on public.ps_din_itens
  for each row execute function public.fn_auditoria();
drop trigger if exists tg_aud_dingrupos on public.ps_din_grupos;
create trigger tg_aud_dingrupos after insert or update or delete on public.ps_din_grupos
  for each row execute function public.fn_auditoria();

alter table public.ps_din_config    enable row level security;
alter table public.ps_din_itens     enable row level security;
alter table public.ps_din_grupos    enable row level security;
alter table public.ps_din_registros enable row level security;

do $$
declare t text;
begin
  foreach t in array array['ps_din_config','ps_din_itens','ps_din_grupos','ps_din_registros'] loop
    execute format('drop policy if exists %I_comite on public.%I', t, t);
    execute format('create policy %I_comite on public.%I for all to authenticated
                    using (public.eh_comite()) with check (public.eh_comite())', t, t);
  end loop;
end $$;

-- ------------------------------------------------------------
-- 7. A JANELA DE TEMPO (o coração da coisa)
--    Uma janela está aberta de (início - tolerância_antes) até
--    (fim + tolerância_depois), no fuso de São Paulo. Fora
--    disso as funções devolvem "fechada" e nada mais — nem
--    lista de candidato, nem registro de grupo, nem roteiro.
-- ------------------------------------------------------------
create or replace function public._din_janela(p_slot uuid)
returns table (slot public.ps_slots, cfg public.ps_din_config,
               abre timestamptz, fecha timestamptz, aberta boolean)
language plpgsql stable security definer
set search_path = public
as $$
declare
  s   public.ps_slots%rowtype;
  c   public.ps_din_config%rowtype;
  tz  text := 'America/Sao_Paulo';
  ini timestamptz; fim timestamptz;
begin
  select * into s from ps_slots where id = p_slot and fase = 'dinamica';
  if not found then return; end if;

  select * into c from ps_din_config where edicao_id = s.edicao_id;
  if not found then
    c.edicao_id := s.edicao_id; c.titulo := 'Dinâmica em grupo';
    c.desafio_titulo := 'Sprint da bancada';
    c.minutos_total := 75; c.tam_grupo := 5;
    c.tolerancia_antes := 30; c.tolerancia_depois := 30;
  end if;

  ini := ((s.data + s.hora_inicio) at time zone tz) - make_interval(mins => c.tolerancia_antes);
  fim := ((s.data + s.hora_fim)    at time zone tz) + make_interval(mins => c.tolerancia_depois);

  slot := s; cfg := c; abre := ini; fecha := fim;
  aberta := now() >= ini and now() <= fim;
  return next;
end $$;
revoke all on function public._din_janela(uuid) from public, anon, authenticated;

create or replace function public._din_por_codigo(p_codigo text)
returns uuid language sql stable security definer
set search_path = public
as $$
  select id from ps_slots
   where fase = 'dinamica' and ativo
     and codigo = upper(regexp_replace(coalesce(p_codigo,''), '[^A-Za-z0-9]', '', 'g'))
   limit 1;
$$;
revoke all on function public._din_por_codigo(text) from public, anon, authenticated;

-- conteúdo ativo de um tipo, já resolvido para a edição/janela
create or replace function public._din_itens(p_edicao uuid, p_slot uuid, p_tipo text)
returns jsonb language sql stable security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'ordem', i.ordem) || i.dados
                            order by i.ordem, i.criado_em), '[]'::jsonb)
    from ps_din_itens i
   where i.tipo = p_tipo and i.ativo
     and (i.edicao_id is null or i.edicao_id = p_edicao)
     and (i.slot_id  is null or i.slot_id  = p_slot);
$$;
revoke all on function public._din_itens(uuid, uuid, text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 8. FUNÇÕES PÚBLICAS (chave anon, sem login)
-- ------------------------------------------------------------

-- 8a. Estado da sala: é o que alimenta o painel projetado e a
--     página do candidato. Fora da janela devolve só o horário
--     em que abre — nenhum conteúdo.
create or replace function public.ps_din_sala(p_codigo text)
returns jsonb language plpgsql stable security definer
set search_path = public
as $$
declare
  v_slot uuid;
  j      record;
  ed     public.ps_edicoes%rowtype;
begin
  v_slot := public._din_por_codigo(p_codigo);
  if v_slot is null then return jsonb_build_object('status','nao_encontrada'); end if;

  select * into j from public._din_janela(v_slot);
  if not found then return jsonb_build_object('status','nao_encontrada'); end if;

  if not j.aberta then
    return jsonb_build_object('status','fechada',
      'abre_em', j.abre, 'fecha_em', j.fecha, 'agora', now());
  end if;

  select * into ed from ps_edicoes where id = (j.slot).edicao_id;

  return jsonb_build_object(
    'status','ok',
    'agora', now(),
    'abre_em', j.abre, 'fecha_em', j.fecha,
    'edicao', jsonb_build_object('nome', ed.nome, 'slug', ed.slug),
    'janela', jsonb_build_object(
      'id', (j.slot).id, 'codigo', (j.slot).codigo, 'data', (j.slot).data,
      'hora_inicio', to_char((j.slot).hora_inicio,'HH24:MI'),
      'hora_fim',    to_char((j.slot).hora_fim,'HH24:MI'),
      'local', (j.slot).local, 'capacidade', (j.slot).capacidade,
      'agendados', (select count(*) from ps_agendamentos a where a.slot_id = (j.slot).id)),
    'config', jsonb_build_object(
      'titulo', (j.cfg).titulo, 'subtitulo', (j.cfg).subtitulo,
      'resumo_equipe', (j.cfg).resumo_equipe,
      'desafio_titulo', (j.cfg).desafio_titulo,
      'desafio_contexto', (j.cfg).desafio_contexto,
      'aviso_lgpd', (j.cfg).aviso_lgpd,
      'wifi_rede', (j.cfg).wifi_rede, 'wifi_senha', (j.cfg).wifi_senha,
      'minutos_total', (j.cfg).minutos_total, 'tam_grupo', (j.cfg).tam_grupo),
    'cartoes',    public._din_itens((j.slot).edicao_id, (j.slot).id, 'cartao'),
    'blocos',     public._din_itens((j.slot).edicao_id, (j.slot).id, 'bloco'),
    'campos',     public._din_itens((j.slot).edicao_id, (j.slot).id, 'campo'),
    'regras',     public._din_itens((j.slot).edicao_id, (j.slot).id, 'regra'),
    'avaliadores',public._din_itens((j.slot).edicao_id, (j.slot).id, 'avaliador'),
    'grupos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', g.id, 'letra', g.letra,
               'pessoas', coalesce(array_length(g.membros,1),0) + coalesce(array_length(g.avulsos,1),0),
               'caso', (select jsonb_build_object('id', i.id) || i.dados
                          from ps_din_itens i where i.id = g.caso_id),
               'versao', coalesce(r.versao,0),
               'atualizado_em', r.atualizado_em)
             order by g.letra)
        from ps_din_grupos g
        left join ps_din_registros r on r.grupo_id = g.id
       where g.slot_id = (j.slot).id), '[]'::jsonb)
  );
end $$;
grant execute on function public.ps_din_sala(text) to anon, authenticated;

-- 8b. O que o grupo já registrou. Só dentro da janela.
create or replace function public.ps_din_registro(p_codigo text, p_grupo uuid)
returns jsonb language plpgsql stable security definer
set search_path = public
as $$
declare
  v_slot uuid; j record; r public.ps_din_registros%rowtype; g public.ps_din_grupos%rowtype;
begin
  v_slot := public._din_por_codigo(p_codigo);
  if v_slot is null then return jsonb_build_object('status','nao_encontrada'); end if;
  select * into j from public._din_janela(v_slot);
  if not found or not j.aberta then return jsonb_build_object('status','fechada'); end if;

  select * into g from ps_din_grupos where id = p_grupo and slot_id = v_slot;
  if not found then return jsonb_build_object('status','grupo_invalido'); end if;

  select * into r from ps_din_registros where grupo_id = p_grupo;
  return jsonb_build_object('status','ok',
    'grupo', jsonb_build_object('id', g.id, 'letra', g.letra,
      'caso', (select jsonb_build_object('id', i.id) || i.dados
                 from ps_din_itens i where i.id = g.caso_id)),
    'dados', coalesce(r.dados, '{}'::jsonb),
    'versao', coalesce(r.versao, 0),
    'atualizado_em', r.atualizado_em,
    'atualizado_por', r.atualizado_por);
end $$;
grant execute on function public.ps_din_registro(text, uuid) to anon, authenticated;

-- 8c. Gravar. p_versao é a versão que o celular tinha quando
--     começou a editar: se o banco já está adiante, ninguém é
--     sobrescrito — devolvemos "conflito" com o texto do banco
--     e a página do candidato oferece as duas versões.
create or replace function public.ps_din_gravar(p_codigo text, p_grupo uuid,
                                                p_dados jsonb, p_versao integer,
                                                p_autor text default null)
returns jsonb language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_slot uuid; j record; r public.ps_din_registros%rowtype;
begin
  v_slot := public._din_por_codigo(p_codigo);
  if v_slot is null then return jsonb_build_object('status','nao_encontrada'); end if;
  select * into j from public._din_janela(v_slot);
  if not found or not j.aberta then return jsonb_build_object('status','fechada'); end if;
  if not exists (select 1 from ps_din_grupos where id = p_grupo and slot_id = v_slot) then
    return jsonb_build_object('status','grupo_invalido');
  end if;
  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then
    return jsonb_build_object('status','dados_invalidos');
  end if;
  if length(p_dados::text) > 24000 then
    return jsonb_build_object('status','longo_demais');
  end if;

  select * into r from ps_din_registros where grupo_id = p_grupo for update;

  if not found then
    insert into ps_din_registros (grupo_id, dados, versao, atualizado_por)
    values (p_grupo, p_dados, 1, nullif(trim(coalesce(p_autor,'')),''))
    returning * into r;
    return jsonb_build_object('status','ok','versao',r.versao,'atualizado_em',r.atualizado_em);
  end if;

  if coalesce(p_versao,-1) <> r.versao then
    return jsonb_build_object('status','conflito','versao',r.versao,
      'dados', r.dados, 'atualizado_em', r.atualizado_em, 'atualizado_por', r.atualizado_por);
  end if;

  update ps_din_registros
     set dados = p_dados, versao = r.versao + 1, atualizado_em = now(),
         atualizado_por = nullif(trim(coalesce(p_autor,'')),'')
   where grupo_id = p_grupo
  returning * into r;

  return jsonb_build_object('status','ok','versao',r.versao,'atualizado_em',r.atualizado_em);
end $$;
grant execute on function public.ps_din_gravar(text, uuid, jsonb, integer, text) to anon, authenticated;

-- ------------------------------------------------------------
-- 9. FUNÇÕES DA MESA DO AVALIADOR (login do SOMA + janela)
--    Mesmo com sessão do comitê, fora da janela não sai dado.
-- ------------------------------------------------------------

-- 9a. As janelas que o avaliador pode abrir agora. Fora do
--     horário a lista volta vazia — é isso que faz a página
--     não existir fora da dinâmica.
create or replace function public.ps_din_janelas()
returns jsonb language plpgsql stable security definer
set search_path = public
as $$
begin
  if not public.eh_comite() then return jsonb_build_object('status','sem_acesso'); end if;
  return jsonb_build_object('status','ok','agora', now(),
    'janelas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', (j.slot).id, 'codigo', (j.slot).codigo, 'data', (j.slot).data,
               'hora_inicio', to_char((j.slot).hora_inicio,'HH24:MI'),
               'hora_fim',    to_char((j.slot).hora_fim,'HH24:MI'),
               'local', (j.slot).local,
               'abre_em', j.abre, 'fecha_em', j.fecha)
             order by (j.slot).data, (j.slot).hora_inicio)
        from ps_slots s
        cross join lateral public._din_janela(s.id) j
       where s.fase = 'dinamica' and s.ativo and j.aberta), '[]'::jsonb));
end $$;
grant execute on function public.ps_din_janelas() to authenticated;

-- 9b. A mesa: candidatos agendados, grupos, registros ao vivo,
--     roteiro, critérios e as avaliações que EU já lancei.
create or replace function public.ps_din_mesa(p_slot uuid)
returns jsonb language plpgsql stable security definer
set search_path = public
as $$
declare j record; ed public.ps_edicoes%rowtype;
begin
  if not public.eh_comite() then return jsonb_build_object('status','sem_acesso'); end if;
  select * into j from public._din_janela(p_slot);
  if not found then return jsonb_build_object('status','nao_encontrada'); end if;
  if not j.aberta then
    return jsonb_build_object('status','fechada','abre_em',j.abre,'fecha_em',j.fecha,'agora',now());
  end if;
  select * into ed from ps_edicoes where id = (j.slot).edicao_id;

  return jsonb_build_object(
    'status','ok', 'agora', now(), 'abre_em', j.abre, 'fecha_em', j.fecha,
    'edicao', jsonb_build_object('id', ed.id, 'nome', ed.nome),
    'janela', jsonb_build_object('id', (j.slot).id, 'codigo', (j.slot).codigo,
      'data', (j.slot).data,
      'hora_inicio', to_char((j.slot).hora_inicio,'HH24:MI'),
      'hora_fim',    to_char((j.slot).hora_fim,'HH24:MI'),
      'local', (j.slot).local),
    'config', jsonb_build_object('titulo',(j.cfg).titulo,'desafio_titulo',(j.cfg).desafio_titulo,
      'desafio_contexto',(j.cfg).desafio_contexto,
      'minutos_total',(j.cfg).minutos_total,'tam_grupo',(j.cfg).tam_grupo),
    'blocos',    public._din_itens((j.slot).edicao_id, (j.slot).id, 'bloco'),
    'criterios', public._din_itens((j.slot).edicao_id, (j.slot).id, 'criterio'),
    'casos',     public._din_itens((j.slot).edicao_id, (j.slot).id, 'caso'),
    'campos',    public._din_itens((j.slot).edicao_id, (j.slot).id, 'campo'),
    'candidatos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'nome', c.nome, 'protocolo', c.protocolo,
               'curso', c.curso, 'periodo', c.periodo,
               'areas', to_jsonb(c.areas_interesse),
               'acessibilidade', c.acessibilidade,
               'compareceu', a.compareceu, 'agendamento_id', a.id)
             order by c.nome)
        from ps_agendamentos a join ps_candidatos c on c.id = a.candidato_id
       where a.slot_id = (j.slot).id), '[]'::jsonb),
    'grupos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', g.id, 'letra', g.letra, 'caso_id', g.caso_id,
               'membros', to_jsonb(g.membros), 'avulsos', to_jsonb(g.avulsos),
               'registro', coalesce(r.dados,'{}'::jsonb),
               'versao', coalesce(r.versao,0), 'atualizado_em', r.atualizado_em)
             order by g.letra)
        from ps_din_grupos g
        left join ps_din_registros r on r.grupo_id = g.id
       where g.slot_id = (j.slot).id), '[]'::jsonb),
    'minhas_avaliacoes', coalesce((
      select jsonb_agg(jsonb_build_object('candidato_id', v.candidato_id,
               'criterios', v.criterios, 'nota', v.nota, 'parecer', v.parecer,
               'recomendacao', v.recomendacao))
        from ps_avaliacoes v
        join ps_agendamentos a on a.candidato_id = v.candidato_id and a.slot_id = (j.slot).id
       where v.fase = 'dinamica' and v.avaliador_id = auth.uid()), '[]'::jsonb)
  );
end $$;
grant execute on function public.ps_din_mesa(uuid) to authenticated;

-- 9c. Formar os grupos (o avaliador arrasta na tela e salva).
--     Recebe [{letra, caso_id, membros:[uuid], avulsos:[texto]}].
create or replace function public.ps_din_grupos_salvar(p_slot uuid, p_grupos jsonb)
returns jsonb language plpgsql volatile security definer
set search_path = public
as $$
declare j record; g jsonb; v_letras text[] := '{}';
begin
  if not public.eh_comite() then return jsonb_build_object('status','sem_acesso'); end if;
  select * into j from public._din_janela(p_slot);
  if not found or not j.aberta then return jsonb_build_object('status','fechada'); end if;
  if jsonb_typeof(coalesce(p_grupos,'null'::jsonb)) <> 'array' then
    return jsonb_build_object('status','dados_invalidos');
  end if;

  for g in select * from jsonb_array_elements(p_grupos) loop
    v_letras := v_letras || upper(trim(g->>'letra'));
    insert into ps_din_grupos (slot_id, letra, caso_id, membros, avulsos)
    values (p_slot, upper(trim(g->>'letra')), nullif(g->>'caso_id','')::uuid,
            coalesce((select array_agg(x::uuid) from jsonb_array_elements_text(g->'membros') x), '{}'),
            coalesce((select array_agg(x)       from jsonb_array_elements_text(g->'avulsos') x), '{}'))
    on conflict (slot_id, letra) do update
      set caso_id = excluded.caso_id,
          membros = excluded.membros,
          avulsos = excluded.avulsos;
  end loop;

  -- grupo que sumiu da tela some do banco (o registro dele vai junto)
  delete from ps_din_grupos where slot_id = p_slot and not (letra = any(v_letras));

  return jsonb_build_object('status','ok',
    'grupos', (select jsonb_agg(jsonb_build_object('id',id,'letra',letra) order by letra)
                 from ps_din_grupos where slot_id = p_slot));
end $$;
grant execute on function public.ps_din_grupos_salvar(uuid, jsonb) to authenticated;

-- 9d. Presença, direto da mesa.
create or replace function public.ps_din_presenca(p_slot uuid, p_candidato uuid, p_veio boolean)
returns jsonb language plpgsql volatile security definer
set search_path = public
as $$
declare j record;
begin
  if not public.eh_comite() then return jsonb_build_object('status','sem_acesso'); end if;
  select * into j from public._din_janela(p_slot);
  if not found or not j.aberta then return jsonb_build_object('status','fechada'); end if;
  update ps_agendamentos set compareceu = p_veio
   where slot_id = p_slot and candidato_id = p_candidato and fase = 'dinamica';
  if not found then return jsonb_build_object('status','nao_encontrada'); end if;
  return jsonb_build_object('status','ok');
end $$;
grant execute on function public.ps_din_presenca(uuid, uuid, boolean) to authenticated;

-- 9e. Lançar a avaliação da dinâmica. Cai na mesma ps_avaliacoes
--     que o SOMA já usa (fase 'dinamica'), então a nota aparece
--     na ficha do candidato sem nenhuma ponte.
create or replace function public.ps_din_avaliar(p_slot uuid, p_candidato uuid,
                                                 p_criterios jsonb, p_parecer text,
                                                 p_recomendacao text)
returns jsonb language plpgsql volatile security definer
set search_path = public
as $$
declare
  j record; v_nota numeric(4,2); v_nome text;
begin
  if not public.eh_comite() then return jsonb_build_object('status','sem_acesso'); end if;
  select * into j from public._din_janela(p_slot);
  if not found or not j.aberta then return jsonb_build_object('status','fechada'); end if;
  if not exists (select 1 from ps_agendamentos
                  where slot_id = p_slot and candidato_id = p_candidato and fase='dinamica') then
    return jsonb_build_object('status','nao_agendado');
  end if;
  if p_recomendacao is not null and p_recomendacao not in ('aprovar','reprovar','em_duvida') then
    return jsonb_build_object('status','dados_invalidos');
  end if;

  select avg(v::numeric) into v_nota
    from jsonb_each_text(coalesce(p_criterios,'{}'::jsonb)) as e(k,v)
   where v ~ '^[0-9]+(\.[0-9]+)?$' and v::numeric > 0;

  select coalesce(nome, email) into v_nome from perfis where id = auth.uid();

  insert into ps_avaliacoes (candidato_id, fase, criterios, nota, parecer,
                             recomendacao, avaliador_id, avaliador)
  values (p_candidato, 'dinamica', coalesce(p_criterios,'{}'::jsonb), v_nota,
          nullif(trim(coalesce(p_parecer,'')),''), p_recomendacao, auth.uid(), v_nome)
  on conflict (candidato_id, fase, avaliador_id) do update
    set criterios = excluded.criterios, nota = excluded.nota,
        parecer = excluded.parecer, recomendacao = excluded.recomendacao,
        avaliador = excluded.avaliador;

  return jsonb_build_object('status','ok','nota',v_nota);
end $$;
grant execute on function public.ps_din_avaliar(uuid, uuid, jsonb, text, text) to authenticated;

-- ------------------------------------------------------------
-- 10. CONTEÚDO INICIAL
--     Roteiro, casos, campos e critérios já prontos para a
--     edição publicada. Tudo editável em SOMA → Seleção →
--     Dinâmica; nada aqui precisa voltar ao SQL Editor.
-- ------------------------------------------------------------
do $$
declare
  v_ed uuid;
begin
  select id into v_ed from ps_edicoes where status = 'publicada' order by criado_em desc limit 1;
  if v_ed is null then
    select id into v_ed from ps_edicoes order by criado_em desc limit 1;
  end if;
  if v_ed is null then return; end if;

  insert into ps_din_config (edicao_id, subtitulo, resumo_equipe, desafio_contexto, aviso_lgpd)
  values (v_ed,
    'Primeira fase presencial do processo seletivo',
    'A NeuroDynamics é uma equipe de pesquisa, desenvolvimento e inovação da Escola de Engenharia da UFMG, sediada no LABBIO, dedicada a tecnologias para a saúde. Percorremos o ciclo completo de um dispositivo: concepção, software e firmware, hardware e validação clínica com quem vai usar.',
    'Vocês vão fazer, em 25 minutos e em grupo, o que a equipe faz no começo de todo projeto: transformar a necessidade de uma pessoa real em um projeto que cabe num semestre. Não existe resposta certa e ninguém precisa saber eletrônica. O que a gente olha é como vocês decidem juntos.',
    'A dinâmica é registrada em ata pelo comitê. Fotos e vídeos só de quem autorizou na inscrição. Avise um avaliador se preferir não aparecer.')
  on conflict (edicao_id) do nothing;

  -- ---- cartões do painel (abertura) ----
  if not exists (select 1 from ps_din_itens where tipo='cartao' and edicao_id = v_ed) then
    insert into ps_din_itens (edicao_id, tipo, ordem, dados) values
    (v_ed,'cartao',10,'{"titulo":"O que a gente faz","texto":"Dispositivos para a saúde, do primeiro requisito até o teste com o usuário. Estimulação elétrica, reabilitação, dispositivos assistivos. Projetos que saem da bancada e chegam em gente."}'),
    (v_ed,'cartao',20,'{"titulo":"Como a gente trabalha","texto":"Cinco departamentos, projetos multidisciplinares, sprints com abertura, daily e fechamento. Cada pessoa tem uma liderança imediata acompanhando o desenvolvimento dela."}'),
    (v_ed,'cartao',30,'{"titulo":"Quem cabe aqui","texto":"Engenharia, saúde, comunicação, gestão, direito, economia. A lista de cursos é um retrato de quem já passou, não uma exigência."}'),
    (v_ed,'cartao',40,'{"titulo":"O que vem depois","texto":"Entrevista individual e período trainee, com um desafio em grupo acompanhado pela equipe até a apresentação final."}');
  end if;

  -- ---- regras da sala ----
  if not exists (select 1 from ps_din_itens where tipo='regra' and edicao_id = v_ed) then
    insert into ps_din_itens (edicao_id, tipo, ordem, dados) values
    (v_ed,'regra',10,'{"texto":"Ninguém é eliminado por falar pouco. É eliminado quem não deixa o outro falar."}'),
    (v_ed,'regra',20,'{"texto":"Não existe resposta certa. Existe decisão defendida com argumento."}'),
    (v_ed,'regra',30,'{"texto":"Um celular por grupo registra. Os outros ficam guardados."}'),
    (v_ed,'regra',40,'{"texto":"O tempo é curto de propósito. Escolher o que não fazer também conta."}');
  end if;

  -- ---- blocos do roteiro (75 min) ----
  if not exists (select 1 from ps_din_itens where tipo='bloco' and edicao_id = v_ed) then
    insert into ps_din_itens (edicao_id, tipo, ordem, dados) values
    (v_ed,'bloco',10,'{"nome":"Chegada e presença","minutos":5,"projetor":"Boas-vindas, código da sala e Wi-Fi","fala":["Receba na porta e confirme o nome na lista da mesa.","Deixe o painel na tela de abertura, com o código grande.","Confira se alguém pediu acessibilidade na inscrição."],"corte":"Nunca. Sem presença não há avaliação."}'),
    (v_ed,'bloco',20,'{"nome":"Abertura","minutos":8,"projetor":"Quem somos, como trabalhamos, o que vem depois","fala":["Apresente-se e apresente os outros avaliadores.","Passe os quatro cartões do painel, um minuto cada.","Diga as regras da sala e o aviso de imagem.","Diga o que acontece hoje e quando sai o resultado."],"corte":"Corte para 5 min juntando os cartões 3 e 4."}'),
    (v_ed,'bloco',30,'{"nome":"Rodada de nomes","minutos":8,"projetor":"Nome, curso e uma coisa que você sabe fazer","fala":["30 segundos por pessoa, em pé, na ordem do círculo.","Corte com gentileza quem passar do tempo, que já vale como sinal.","Anote na mesa quem citou o quê: ajuda a formar os grupos."],"corte":"Com mais de 12 pessoas, peça só nome, curso e uma habilidade."}'),
    (v_ed,'bloco',40,'{"nome":"Briefing e grupos","minutos":5,"projetor":"O desafio e o QR de registro","fala":["Leia o caso em voz alta, inteiro, uma vez só.","Divida os grupos pela mesa e diga a letra de cada um em voz alta.","Peça que um celular por grupo abra o QR e entre com o código.","Mostre os cinco campos do registro no painel."],"corte":"Nunca. É o bloco que faz o resto funcionar."}'),
    (v_ed,'bloco',50,'{"nome":"Trabalho em grupo","minutos":25,"projetor":"Cronômetro, campos do registro e avisos de tempo","fala":["Circule entre os grupos, sem sentar e sem resolver por eles.","Avise em voz alta aos 15, aos 5 e ao último minuto.","Se um grupo travar, pergunte: quem é a pessoa e o que muda no dia dela?","Se alguém dominar, peça a opinião de quem ainda não falou."],"corte":"Vá para 18 min. Menos que isso não dá para observar ninguém."}'),
    (v_ed,'bloco',60,'{"nome":"Apresentações","minutos":15,"projetor":"Grupo da vez, cronômetro de 3 min e o registro na tela","fala":["3 minutos por grupo, com o registro do grupo projetado.","Quem apresenta não pode ser quem escreveu. Combine antes.","Uma pergunta por grupo, feita por um avaliador diferente a cada vez.","Boa pergunta: o que vocês decidiram não fazer, e por quê?"],"corte":"2 min de fala e nenhuma pergunta, se o horário apertar."}'),
    (v_ed,'bloco',70,'{"nome":"Fechamento","minutos":6,"projetor":"Próximos passos, prazo do resultado e onde acompanhar","fala":["Diga a data do resultado e onde ele sai (site, Acompanhar).","Abra para duas ou três perguntas, não mais.","Agradeça pelo nome de quem você conseguiu decorar.","Combine com a mesa: 5 min de calibração depois que todos saírem."],"corte":"Nunca. É o bloco que faz a pessoa sair querendo voltar."}');
  end if;

  -- ---- casos do desafio ----
  if not exists (select 1 from ps_din_itens where tipo='caso' and edicao_id = v_ed) then
    insert into ps_din_itens (edicao_id, tipo, ordem, dados) values
    (v_ed,'caso',10,'{"titulo":"A mão que não solta","pessoa":"Homem, 34 anos, sequela de AVC há dois anos. Move o braço direito, mas não consegue abrir a mão sozinho para soltar um objeto.","necessidade":"Voltar a comer sozinho em público sem depender de alguém para abrir a mão dele.","restricoes":["Vai usar em casa e na rua, sem ninguém para ajustar","Não pode chamar atenção em um restaurante","O laboratório tem seis meses e três pessoas para isso"],"pista":"Pergunte o que ele já faz hoje para se virar. O contorno atual costuma valer mais que a solução ideal."}'),
    (v_ed,'caso',20,'{"titulo":"O treino que ninguém vê","pessoa":"Mulher, 27 anos, lesão medular, treina três vezes por semana com estimulação elétrica para pedalar em um triciclo adaptado.","necessidade":"Saber se está evoluindo entre um treino e outro, coisa que hoje ninguém consegue dizer.","restricoes":["Quem acompanha o treino é um fisioterapeuta, não um engenheiro","O triciclo já existe e não pode ser trocado","A resposta precisa aparecer no mesmo dia do treino"],"pista":"Pergunte quem lê o resultado. A medida que ninguém entende não muda nada."}'),
    (v_ed,'caso',30,'{"titulo":"A cadeira que some","pessoa":"Adolescente, 16 anos, paralisia cerebral, usa cadeira de rodas motorizada e estuda em escola pública.","necessidade":"Chamar alguém quando a cadeira trava ou a bateria acaba longe da sala.","restricoes":["A escola não tem Wi-Fi confiável","A família não pode pagar mensalidade de serviço","Precisa funcionar com a mão que ele controla melhor"],"pista":"Pergunte quem atende o chamado. Aviso sem alguém do outro lado é só barulho."}'),
    (v_ed,'caso',40,'{"titulo":"A prótese que dói no fim do dia","pessoa":"Homem, 41 anos, amputação transfemoral, usa prótese há cinco anos e trabalha em pé.","necessidade":"Descobrir em que momento do dia o coto começa a sofrer, antes da ferida aparecer.","restricoes":["Ele não vai carregar mais nada além da prótese","Consulta com o protesista só de dois em dois meses","O dado precisa fazer sentido para o protesista, não para ele"],"pista":"Pergunte o que ele faria com o aviso. Medir sem ação é diagnóstico de nada."}');
  end if;

  -- ---- campos do registro ----
  if not exists (select 1 from ps_din_itens where tipo='campo' and edicao_id = v_ed) then
    insert into ps_din_itens (edicao_id, tipo, ordem, dados) values
    (v_ed,'campo',10,'{"chave":"pessoa","rotulo":"Quem é e o que muda na vida dela","ajuda":"Uma frase. Se o dispositivo funcionar, o que essa pessoa passa a fazer amanhã?","limite":300,"linhas":3}'),
    (v_ed,'campo',20,'{"chave":"solucao","rotulo":"O mínimo que resolve","ajuda":"O que o dispositivo faz. Sem marca, sem componente, sem sigla: o que ele faz.","limite":400,"linhas":4}'),
    (v_ed,'campo',30,'{"chave":"teste","rotulo":"Como vocês saberiam que funcionou","ajuda":"Um teste concreto, com quem, onde e o que seria medido.","limite":400,"linhas":4}'),
    (v_ed,'campo',40,'{"chave":"risco","rotulo":"O maior risco do projeto","ajuda":"O que faria isso dar errado, e o que vocês fariam na primeira semana para descobrir.","limite":300,"linhas":3}'),
    (v_ed,'campo',50,'{"chave":"time","rotulo":"Quem faz o quê nas duas primeiras semanas","ajuda":"O nome de cada pessoa do grupo e a primeira entrega dela. Use o que cada um sabe.","limite":500,"linhas":5}');
  end if;

  -- ---- critérios com âncoras ----
  if not exists (select 1 from ps_din_itens where tipo='criterio' and edicao_id = v_ed) then
    insert into ps_din_itens (edicao_id, tipo, ordem, dados) values
    (v_ed,'criterio',10,'{"nome":"Comunicação","a1":"Fala pouco ou fala sem ser entendido; não sustenta a ideia quando questionado.","a3":"Expõe a ideia com clareza e responde ao que perguntam.","a5":"Organiza a ideia do grupo em palavras que qualquer um da sala entende, inclusive quem é de outra área."}'),
    (v_ed,'criterio',20,'{"nome":"Trabalho em equipe","a1":"Trabalha sozinho no meio do grupo, ou atropela quem discorda.","a3":"Ouve, incorpora ideia dos outros e cede quando o argumento é melhor.","a5":"Puxa para dentro quem estava fora, e nomeia a contribuição alheia sem ser pedido."}'),
    (v_ed,'criterio',30,'{"nome":"Proatividade","a1":"Espera instrução; só age quando alguém distribui tarefa.","a3":"Assume uma parte do trabalho por conta própria e entrega.","a5":"Organiza o grupo no primeiro minuto, propõe um caminho e revisa quando não funciona."}'),
    (v_ed,'criterio',40,'{"nome":"Resolução de problemas","a1":"Fica no genérico, ou pula para a solução sem entender o problema.","a3":"Separa o essencial do acessório e justifica o recorte.","a5":"Faz a pergunta que muda o rumo do grupo e transforma restrição em decisão de projeto."}'),
    (v_ed,'criterio',50,'{"nome":"Alinhamento com a equipe","a1":"Trata a pessoa do caso como detalhe; busca a resposta que impressiona.","a3":"Mantém o usuário no centro e demonstra interesse real pelo trabalho da equipe.","a5":"Argumenta pelo usuário mesmo quando é o caminho mais chato, e demonstra que veio saber o que fazemos."}');
  end if;
end $$;

-- ============================================================
-- FIM DA MIGRAÇÃO SOMA 12.0
-- ============================================================
