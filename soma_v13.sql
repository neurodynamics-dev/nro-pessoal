-- ============================================================
-- SOMA 13.0 — MIGRAÇÃO · NeuroDynamics
-- SITE INSTITUCIONAL EM TRÊS IDIOMAS: o site neurodynamics.dev
-- passa a ter versão em inglês, português e francês, com
-- seletor no cabeçalho. Os textos das páginas moram no próprio
-- index.html (bloco "L"); o que vive no banco são os projetos,
-- que agora ganham colunas de tradução.
--
-- Campos por idioma (o inglês continua nas colunas originais):
--   tagline / tagline_pt / tagline_fr
--   resumo  / resumo_pt  / resumo_fr
--   descricao / descricao_pt / descricao_fr
-- Nome, status e tags continuam únicos: o site traduz status e
-- tags por dicionário, e os nomes dos projetos não se traduzem.
--
-- Pré-requisito: SOMA 9.0 aplicada (tabela site_projetos).
-- Idempotente: pode rodar mais de uma vez sem duplicar nada.
-- COMO USAR: cole o arquivo INTEIRO no SQL Editor e Run.
--
-- ATENÇÃO ao copiar SQL para o Supabase: o travessão (—) dentro
-- de uma string vira "--" em alguns caminhos de cópia, o que
-- comenta o resto da linha e quebra a migração (foi o que
-- aconteceu com a soma_v9). Por isso os textos abaixo usam
-- somente pontuação simples. Acentos são seguros.
-- ============================================================

-- ------------------------------------------------------------
-- 1. COLUNAS DE TRADUÇÃO
-- ------------------------------------------------------------
alter table public.site_projetos add column if not exists tagline_pt   text;
alter table public.site_projetos add column if not exists resumo_pt    text;
alter table public.site_projetos add column if not exists descricao_pt text;
alter table public.site_projetos add column if not exists tagline_fr   text;
alter table public.site_projetos add column if not exists resumo_fr    text;
alter table public.site_projetos add column if not exists descricao_fr text;

-- ------------------------------------------------------------
-- 2. FUNÇÃO PÚBLICA — devolve os três idiomas de uma vez.
--    O site escolhe o idioma ativo e cai no inglês quando a
--    tradução ainda não foi preenchida.
-- ------------------------------------------------------------
create or replace function public.site_projetos_publico()
returns jsonb language sql stable security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'slug', p.slug, 'nome', p.nome,
    'tagline', p.tagline, 'tagline_pt', p.tagline_pt, 'tagline_fr', p.tagline_fr,
    'resumo', p.resumo, 'resumo_pt', p.resumo_pt, 'resumo_fr', p.resumo_fr,
    'descricao', p.descricao, 'descricao_pt', p.descricao_pt, 'descricao_fr', p.descricao_fr,
    'status', p.status, 'tags', to_jsonb(p.tags),
    'imagem_url', p.imagem_url
  ) order by p.ordem, p.nome), '[]'::jsonb)
  from site_projetos p
  where p.publicado;
$$;
grant execute on function public.site_projetos_publico() to anon, authenticated;

-- ------------------------------------------------------------
-- 3. TRADUÇÕES DOS CINCO PROJETOS DA CARGA INICIAL
--    Só preenche o que ainda estiver vazio (as colunas acabaram
--    de nascer), então nada que tenha sido editado no painel é
--    sobrescrito. O texto em inglês não é tocado.
-- ------------------------------------------------------------
update public.site_projetos p set
  tagline_pt   = coalesce(p.tagline_pt,   t.tagline_pt),
  resumo_pt    = coalesce(p.resumo_pt,    t.resumo_pt),
  descricao_pt = coalesce(p.descricao_pt, t.descricao_pt),
  tagline_fr   = coalesce(p.tagline_fr,   t.tagline_fr),
  resumo_fr    = coalesce(p.resumo_fr,    t.resumo_fr),
  descricao_fr = coalesce(p.descricao_fr, t.descricao_fr)
from (values

  ('calima',
   'Monitoramento que acompanha o paciente',
   'Uma plataforma de monitoramento inteligente que une sensoriamento embarcado e inteligência no próprio dispositivo, feita para acompanhar o paciente além da clínica.',
   'A Calima une sensoriamento embarcado e inteligência no próprio dispositivo para acompanhar o paciente além das paredes da clínica. O projeto cobre a pilha inteira: o hardware dos sensores, o firmware de tempo real e os modelos que destilam o sinal bruto em informação na qual um profissional pode confiar.',
   'Un suivi qui accompagne le patient',
   'Une plateforme de surveillance intelligente qui associe capteurs embarqués et intelligence sur l''appareil, conçue pour suivre le patient au-delà de la clinique.',
   'Calima associe capteurs embarqués et intelligence sur l''appareil pour suivre le patient au-delà des murs de la clinique. Le projet couvre toute la chaîne : le matériel des capteurs, le firmware temps réel et les modèles qui distillent le signal brut en information digne de la confiance du clinicien.'),

  ('opalina',
   'Dados clínicos, tornados legíveis',
   'Uma plataforma de software que torna dados clínicos fragmentados claros e utilizáveis para as equipes que agem sobre eles.',
   'A Opalina é uma plataforma de software que torna dados clínicos fragmentados claros e utilizáveis. Começou como uma pergunta de pesquisa sobre como as equipes de cuidado realmente decidem, e cresceu para explorar como deveria ser o apoio à decisão quando é desenhado em torno de pessoas, não de painéis.',
   'Les données cliniques, rendues lisibles',
   'Une plateforme logicielle qui rend les données cliniques fragmentées claires et exploitables pour les équipes qui agissent.',
   'Opalina est une plateforme logicielle qui rend claires et exploitables des données cliniques fragmentées. Née d''une question de recherche sur la façon dont les équipes soignantes décident réellement, elle explore ce que devrait être l''aide à la décision lorsqu''elle est conçue autour des personnes, et non des tableaux de bord.'),

  ('orion',
   'Instrumentação sem concessões',
   'Instrumentação projetada para procedimentos em que a precisão não é negociável: hardware, firmware e software desenhados como um só.',
   'Órion é instrumentação para procedimentos em que a precisão não é negociável. Hardware, firmware e software são projetados como um único sistema, com cada camada desenhada, simulada e testada dentro de casa.',
   'L''instrumentation sans compromis',
   'Une instrumentation conçue pour des gestes où la précision ne se négocie pas : matériel, firmware et logiciel pensés comme un tout.',
   'Órion est une instrumentation destinée aux gestes où la précision ne se négocie pas. Matériel, firmware et logiciel forment un seul système, chaque couche étant conçue, simulée et testée en interne.'),

  ('deriva',
   'Movimento, medido',
   'Tecnologia que lê o movimento humano e o traduz em medidas objetivas para reabilitação e acompanhamento.',
   'A Deriva lê o movimento humano e o traduz em medidas objetivas para reabilitação e acompanhamento. Sensores vestíveis, processamento de sinais e inteligência de máquina trabalham juntos para que o progresso possa ser visto, e não apenas sentido.',
   'Le mouvement, mesuré',
   'Une technologie qui lit le mouvement humain et le traduit en mesures objectives pour la rééducation et le suivi.',
   'Deriva lit le mouvement humain et le traduit en mesures objectives pour la rééducation et le suivi. Capteurs portés, traitement du signal et intelligence artificielle travaillent ensemble pour que les progrès se voient, et ne soient pas seulement ressentis.'),

  ('nebula',
   'A camada que conecta',
   'Infraestrutura segura que faz dispositivos, software e pessoas falarem a mesma língua em todo o nosso ecossistema.',
   'A Nebula é a camada que conecta o nosso ecossistema: a infraestrutura que faz dispositivos, software e pessoas falarem a mesma língua. Discreta por projeto, ela leva os dados com segurança entre cada projeto e onde eles precisam chegar.',
   'La couche qui relie',
   'Une infrastructure sécurisée qui permet aux appareils, aux logiciels et aux personnes de parler la même langue dans tout notre écosystème.',
   'Nebula est la couche qui relie notre écosystème : l''infrastructure qui permet aux appareils, aux logiciels et aux personnes de parler la même langue. Discrète par conception, elle transporte les données en toute sécurité entre chaque projet et leur destination.')

) as t(slug, tagline_pt, resumo_pt, descricao_pt, tagline_fr, resumo_fr, descricao_fr)
where p.slug = t.slug;

-- ============================================================
-- FIM — SOMA 13.0
-- Depois desta migração:
--   1) publique o site atualizado (site/index.html e admin.html);
--   2) o painel passa a ter abas EN / PT / FR nos campos de
--      texto de cada projeto. O que ficar vazio em português ou
--      francês cai automaticamente no texto em inglês.
-- ============================================================
