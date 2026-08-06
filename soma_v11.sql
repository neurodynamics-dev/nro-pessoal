-- ============================================================
-- SOMA 11.0 — MIGRAÇÃO · NeuroDynamics
-- 1) FAQ do site do processo seletivo: as perguntas frequentes
--    saem do código do site e passam a ser editadas pelo SOMA
--    (Seleção → FAQ), como etapas e publicações já são.
-- 2) Competências do candidato: um catálogo de habilidades que
--    giram em torno do que a equipe faz. Na inscrição, o
--    candidato marca as que já tem e as que quer desenvolver;
--    o comitê ajusta as duas listas durante as fases, na ficha.
--
-- Pré-requisito: SOMA 6.0 aplicada.
-- Idempotente: pode rodar mais de uma vez sem duplicar nada.
-- COMO USAR: cole o arquivo INTEIRO no SQL Editor e Run.
-- ============================================================

-- ------------------------------------------------------------
-- 1. TABELA
--    edicao_id nulo = pergunta vale para todas as edições, que
--    é o caso da maioria delas. Preencha a edição só quando a
--    resposta valer apenas para aquele processo.
--    A resposta aceita uma marcação mínima, entendida pelo
--    site: *negrito*, [texto](https://link) e quebras de linha.
-- ------------------------------------------------------------
create table if not exists public.ps_faq (
  id         uuid primary key default gen_random_uuid(),
  edicao_id  uuid references public.ps_edicoes(id) on delete cascade,
  ordem      integer not null default 100,
  pergunta   text not null,
  resposta   text not null,
  publicada  boolean not null default true,
  criado_em  timestamptz not null default now()
);
create index if not exists idx_psfaq_ordem on public.ps_faq (edicao_id, ordem);

-- ------------------------------------------------------------
-- 2. AUDITORIA (mesmo gatilho das demais tabelas do sistema)
-- ------------------------------------------------------------
drop trigger if exists tg_aud_psfaq on public.ps_faq;
create trigger tg_aud_psfaq after insert or update or delete on public.ps_faq
  for each row execute function public.fn_auditoria();

-- ------------------------------------------------------------
-- 3. SEGURANÇA (RLS)
--    Sem política para "anon": o site público lê o FAQ apenas
--    pela função ps_site(), que devolve só o que está
--    publicado. Escrita segue a regra do módulo — comitê de
--    seleção, admin e pessoal.
-- ------------------------------------------------------------
alter table public.ps_faq enable row level security;
drop policy if exists ps_faq_comite on public.ps_faq;
create policy ps_faq_comite on public.ps_faq for all to authenticated
  using (public.eh_comite()) with check (public.eh_comite());

-- ------------------------------------------------------------
-- 4. COMPETÊNCIAS
--    Catálogo do que a equipe faz, agrupado por frente. O site
--    monta as etiquetas da inscrição a partir daqui; desligue
--    "ativa" para aposentar uma etiqueta sem perder o histórico
--    de quem já a marcou.
-- ------------------------------------------------------------
create table if not exists public.ps_competencias (
  id     uuid primary key default gen_random_uuid(),
  grupo  text not null,
  nome   text not null unique,
  ordem  integer not null default 100,
  ativa  boolean not null default true
);
create index if not exists idx_pscomp_ordem on public.ps_competencias (ordem, nome);

--    Duas listas por candidato: o que já traz e o que quer
--    desenvolver. São texto livre de propósito — uma etiqueta
--    aposentada no catálogo não some da ficha de ninguém.
alter table public.ps_candidatos
  add column if not exists competencias           text[] not null default '{}',
  add column if not exists competencias_desejadas text[] not null default '{}';

alter table public.ps_competencias enable row level security;
--    O catálogo não tem segredo: qualquer autenticado lê, e a
--    escrita segue a regra do módulo.
drop policy if exists pscomp_select on public.ps_competencias;
create policy pscomp_select on public.ps_competencias for select to authenticated using (true);
drop policy if exists pscomp_write on public.ps_competencias;
create policy pscomp_write on public.ps_competencias for all to authenticated
  using (public.eh_comite()) with check (public.eh_comite());

drop trigger if exists tg_aud_pscomp on public.ps_competencias;
create trigger tg_aud_pscomp after insert or update or delete on public.ps_competencias
  for each row execute function public.fn_auditoria();

-- ------------------------------------------------------------
-- 5. ps_site() — mesma função da soma_v6.sql, agora devolvendo
--    também o FAQ (as perguntas da edição publicada mais as
--    gerais, que valem para qualquer edição) e o catálogo de
--    competências que a inscrição precisa exibir.
-- ------------------------------------------------------------
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
    'faq', coalesce((
      select jsonb_agg(jsonb_build_object(
        'pergunta', f.pergunta, 'resposta', f.resposta
      ) order by f.ordem, f.criado_em)
      from ps_faq f
      where f.publicada and (f.edicao_id is null or f.edicao_id = v_ed.id)
    ), '[]'::jsonb),
    'competencias', coalesce((
      select jsonb_agg(jsonb_build_object('grupo', c.grupo, 'nome', c.nome)
                       order by c.ordem, c.nome)
      from ps_competencias c where c.ativa
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

-- ------------------------------------------------------------
-- 6. ps_inscrever() — mesma função da soma_v6.sql, agora
--    guardando também as duas listas de competências que o
--    candidato marca no formulário.
-- ------------------------------------------------------------
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
    areas_interesse, competencias, competencias_desejadas,
    motivacao, disponibilidade, como_soube,
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
    coalesce((select array_agg(left(x,80)) from jsonb_array_elements_text(
      case when jsonb_typeof(p->'competencias')='array'
           then p->'competencias' else '[]'::jsonb end) x), '{}'),
    coalesce((select array_agg(left(x,80)) from jsonb_array_elements_text(
      case when jsonb_typeof(p->'competencias_desejadas')='array'
           then p->'competencias_desejadas' else '[]'::jsonb end) x), '{}'),
    left(p->>'motivacao',4000), left(p->>'disponibilidade',60), left(p->>'como_soube',120),
    true, true, coalesce((p->>'autorizacao_imagem')::boolean, false))
  returning id, numero into v_id, v_num;

  v_prot := 'PS' || to_char(v_hoje,'YY') || '-' || lpad(v_num::text, 4, '0');
  update ps_candidatos set protocolo = v_prot where id = v_id;

  return jsonb_build_object('status','ok','protocolo',v_prot);
end $$;
grant execute on function public.ps_inscrever(jsonb) to anon, authenticated;

-- ------------------------------------------------------------
-- 7. CONTEÚDO INICIAL
--    Só entra se a tabela estiver vazia: rodar de novo não
--    duplica nem sobrescreve o que o comitê já editou.
--    São as mesmas perguntas que o site trazia no código.
-- ------------------------------------------------------------
insert into public.ps_faq (ordem, pergunta, resposta)
select * from (values
  (10, 'Preciso ser aluno da UFMG para participar?',
   'Sim para a maior parte das vagas, mas não só: qualquer estudante é bem-vindo, inclusive de ensino técnico — como o COLTEC. Não exigimos curso nem período específicos, e não é preciso ser da engenharia. Os requisitos formais estão no edital, que prevalece sobre este site.'),
  (20, 'Preciso ter experiência prévia?',
   'Não. Avaliamos potencial, comprometimento e vontade de aprender. O período trainee existe justamente para dar a base necessária, com o acompanhamento dos membros da equipe.'),
  (30, 'As atividades exigem dedicação presencial?',
   'As reuniões gerais, normalmente uma vez por mês, são presenciais. O resto varia com a necessidade de cada projeto: bancada, teste e validação acontecem no laboratório, e boa parte do trabalho se resolve de onde você estiver. Na prática, *desde que as entregas aconteçam no prazo combinado, o lugar onde você trabalha é escolha sua.*'),
  (40, 'Qual a contrapartida da minha participação na equipe?',
   'A participação é *voluntária e não remunerada* — somos uma equipe universitária, e o que ela oferece não é salário.

O que você leva daqui é outra coisa: responsabilidade real sobre uma entrega, dentro de projetos de tecnologia em saúde que vão do levantamento de requisitos à validação clínica. Prática de trabalho em equipe multidisciplinar, com metodologia ágil, prazos acordados e uma liderança próxima acompanhando seu crescimento. Contato com pesquisa, laboratórios, hospitais, parceiros e competições internacionais. E um portfólio que você defende em qualquer entrevista, porque foi você que construiu.

Some-se a isso a possibilidade de aproveitamento acadêmico das atividades e a rede de pessoas que continua depois que a graduação acaba.'),
  (50, 'Como a equipe se organiza?',
   'São cinco departamentos: *Pessoal*, *Marketing*, *Relações Institucionais*, *Clínica* e *P&D*. Os projetos ficam dentro do P&D. Cada projeto tem um supervisor e cada departamento, um gerente.

Os times trabalham com metodologias ágeis, no estilo Scrum: abertura de sprint, daily e fechamento de sprint, com as entregas acompanhadas em ferramentas de gestão de projetos. O organograma é bem definido de propósito — assim cada membro tem a liderança imediata por perto para apoiar seu crescimento pessoal e profissional.'),
  (60, 'Como faço o aproveitamento das atividades no meu curso?',
   'Isso depende diretamente das normas do seu colegiado. Procure a coordenação do seu curso para saber se existe essa possibilidade e quais são os requisitos formais para o aproveitamento como *AACC* (Atividade Acadêmica Curricular Complementar).

A depender das normas e das atividades que você executar, a forma de aproveitamento varia: iniciação científica, extensão, equipe de competição, participação em eventos ou as produções geradas, como publicações.'),
  (70, 'Posso aproveitar a participação como estágio?',
   'Isso vai depender diretamente do seu colegiado. Para alunos do COLTEC, que em geral podem aproveitar atividades extracurriculares como estágio, pode ser possível. Para os demais tende a ser complicado: a NeuroDynamics não possui registro que permita o vínculo formal de estagiário de graduação.'),
  (80, 'Preciso criar uma conta no site?',
   'Não. Ao se inscrever, você recebe um *protocolo*. Com ele e o e-mail cadastrado, você acompanha sua situação, agenda a dinâmica e a entrevista e consulta os resultados.'),
  (90, 'Como funcionam as fases?',
   'Após a análise das inscrições, os candidatos deferidos participam de uma dinâmica em grupo. Os aprovados seguem para uma entrevista individual e, na sequência, para o período trainee, que termina com uma apresentação final e o resultado definitivo.'),
  (100, 'O que é o período trainee?',
   'É a fase em que você já atua dentro da equipe. Os trainees desenvolvem em grupo um desafio multidisciplinar, que passa pelas diferentes áreas da NeuroDynamics, com o acompanhamento dos membros até a apresentação final.'),
  (110, 'Como fico sabendo dos resultados?',
   'Os resultados de todas as fases são publicados na página *Edital e resultados*. Você também pode consultar sua situação individual em *Acompanhar*, informando protocolo e e-mail.'),
  (120, 'Onde conheço melhor o trabalho da equipe?',
   'A página *A NeuroDynamics* conta como a equipe se organiza e reúne as reportagens sobre o que fazemos. Para conhecer os projetos a fundo, as parcerias e as áreas de atuação, o lugar é o site institucional: [neurodynamics.dev](https://neurodynamics.dev).')
) as novo(ordem, pergunta, resposta)
where not exists (select 1 from public.ps_faq);

--    Catálogo de competências. A ordem agrupa por frente; o
--    nome é único, então rodar de novo não duplica — e uma
--    etiqueta nova é só acrescentar uma linha aqui ou criar
--    pelo SOMA.
insert into public.ps_competencias (grupo, nome, ordem) values
  ('P&D · Software', 'Programação de firmware',            10),
  ('P&D · Software', 'Sistemas embarcados',                11),
  ('P&D · Software', 'Processamento de sinais',            12),
  ('P&D · Software', 'Visão computacional',                13),
  ('P&D · Software', 'Aprendizado de máquina',             14),
  ('P&D · Software', 'Desenvolvimento web',                15),
  ('P&D · Software', 'Aplicativos móveis',                 16),
  ('P&D · Software', 'Banco de dados',                     17),
  ('P&D · Software', 'Controle e automação',               18),
  ('P&D · Software', 'Interface e experiência (UI/UX)',    19),
  ('P&D · Hardware', 'Eletrônica analógica',               20),
  ('P&D · Hardware', 'Eletrônica digital',                 21),
  ('P&D · Hardware', 'Projeto de placas (PCB)',            22),
  ('P&D · Hardware', 'Instrumentação e sensores',          23),
  ('P&D · Hardware', 'Soldagem e montagem',                24),
  ('P&D · Hardware', 'Modelagem 3D (CAD)',                 25),
  ('P&D · Hardware', 'Impressão 3D e prototipagem',        26),
  ('P&D · Hardware', 'Usinagem e fabricação',              27),
  ('P&D · Hardware', 'Projeto mecânico',                   28),
  ('P&D · Hardware', 'Simulação e elementos finitos',      29),
  ('Clínica',        'Anatomia e fisiologia',              30),
  ('Clínica',        'Biomecânica',                        31),
  ('Clínica',        'Reabilitação e fisioterapia',        32),
  ('Clínica',        'Protocolos de ensaio clínico',       33),
  ('Clínica',        'Ética em pesquisa (CEP)',            34),
  ('Clínica',        'Acompanhamento de usuários',         35),
  ('Clínica',        'Análise de dados clínicos',          36),
  ('Relações Institucionais', 'Financiamento público (editais)',   40),
  ('Relações Institucionais', 'Prospecção de patrocinadores',      41),
  ('Relações Institucionais', 'Elaboração de projetos e propostas',42),
  ('Relações Institucionais', 'Prestação de contas',               43),
  ('Relações Institucionais', 'Convênios e parcerias',             44),
  ('Relações Institucionais', 'Propriedade intelectual e patentes',45),
  ('Marketing',      'Edição de vídeo',                    50),
  ('Marketing',      'Fotografia',                         51),
  ('Marketing',      'Design gráfico',                     52),
  ('Marketing',      'Identidade visual',                  53),
  ('Marketing',      'Redes sociais',                      54),
  ('Marketing',      'Redação e roteiro',                  55),
  ('Marketing',      'Divulgação científica',              56),
  ('Marketing',      'Assessoria de imprensa',             57),
  ('Marketing',      'Produção de eventos',                58),
  ('Pessoal e gestão', 'Gestão de projetos',               60),
  ('Pessoal e gestão', 'Metodologias ágeis (Scrum)',       61),
  ('Pessoal e gestão', 'Recrutamento e seleção',           62),
  ('Pessoal e gestão', 'Treinamento e desenvolvimento',    63),
  ('Pessoal e gestão', 'Documentação e processos',         64),
  ('Pessoal e gestão', 'Planejamento financeiro',          65)
on conflict (nome) do nothing;

-- ------------------------------------------------------------
-- PRONTO. Conferências úteis:
--   1) o que o site vai mostrar:
--      select ordem, pergunta from ps_faq where publicada order by ordem;
--   2) o que a função devolve:  select public.ps_site() -> 'faq';
--   3) o catálogo de etiquetas:
--      select grupo, nome from ps_competencias where ativa order by ordem;
--   4) quem marcou o quê:
--      select nome, competencias, competencias_desejadas from ps_candidatos;
--   5) edição do conteúdo: SOMA → Seleção → FAQ / ficha do candidato
-- ============================================================
