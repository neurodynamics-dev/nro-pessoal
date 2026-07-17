-- ============================================================
-- SOMA 9.0 — MIGRAÇÃO · NeuroDynamics
-- Conteúdo do SITE INSTITUCIONAL (neurodynamics.dev):
-- tabela de projetos exibidos nas páginas "Projects" e na
-- home, com edição pelo painel site/admin.html (login com a
-- mesma conta do SOMA, papéis admin/pessoal).
--
-- O site público lê os projetos pela função site_projetos_publico()
-- (chave anon); se o banco estiver fora, o site continua no ar
-- com o conteúdo de reserva embutido no index.html.
--
-- Pré-requisito: SOMA 8.0 aplicada.
-- Idempotente: pode rodar mais de uma vez sem duplicar nada.
-- COMO USAR: cole o arquivo INTEIRO no SQL Editor e Run.
-- ============================================================

-- ------------------------------------------------------------
-- 1. PROJETOS DO SITE
--    Os textos são exibidos em inglês no site — preencha os
--    campos já em inglês. "resumo" aparece no cartão da home;
--    "descricao" na página de projetos. "imagem_url" substitui
--    o placeholder quando preenchida.
-- ------------------------------------------------------------
create table if not exists public.site_projetos (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique,
  nome          text not null,
  tagline       text,                            -- linha curta sob o título
  resumo        text,                            -- cartão da home (1–2 frases)
  descricao     text,                            -- página de projetos (parágrafo)
  status        text not null default 'In development',  -- rótulo livre, em inglês
  tags          text[] not null default '{}',    -- ex.: {Software, Firmware, AI}
  imagem_url    text,                            -- vazio = placeholder do site
  ordem         integer not null default 100,
  publicado     boolean not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists idx_siteprj_ordem on public.site_projetos (publicado, ordem);

drop trigger if exists tg_upd_siteprj on public.site_projetos;
create trigger tg_upd_siteprj before update on public.site_projetos
  for each row execute function public.fn_atualizado();

-- ------------------------------------------------------------
-- 2. SEGURANÇA
--    Nenhum acesso direto para anon (o público lê pela função
--    abaixo). Autenticados consultam; só admin/pessoal editam.
-- ------------------------------------------------------------
alter table public.site_projetos enable row level security;

drop policy if exists siteprj_select on public.site_projetos;
create policy siteprj_select on public.site_projetos
  for select to authenticated using (true);

drop policy if exists siteprj_write on public.site_projetos;
create policy siteprj_write on public.site_projetos
  for all to authenticated
  using (public.papel_atual() in ('admin','pessoal'))
  with check (public.papel_atual() in ('admin','pessoal'));

-- ------------------------------------------------------------
-- 3. FUNÇÃO PÚBLICA (chamada pelo site com a chave anon)
--    Devolve só os projetos publicados, na ordem de exibição.
-- ------------------------------------------------------------
create or replace function public.site_projetos_publico()
returns jsonb language sql stable security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'slug', p.slug, 'nome', p.nome, 'tagline', p.tagline,
    'resumo', p.resumo, 'descricao', p.descricao,
    'status', p.status, 'tags', to_jsonb(p.tags),
    'imagem_url', p.imagem_url
  ) order by p.ordem, p.nome), '[]'::jsonb)
  from site_projetos p
  where p.publicado;
$$;
grant execute on function public.site_projetos_publico() to anon, authenticated;

-- ------------------------------------------------------------
-- 4. CARGA INICIAL — só roda com a tabela vazia; depois disso
--    a gestão é toda pelo painel site/admin.html.
-- ------------------------------------------------------------
insert into public.site_projetos
  (slug, nome, tagline, resumo, descricao, status, tags, ordem)
select * from (values
  ('calima', 'Calima', 'Monitoring that follows the patient',
   'An intelligent monitoring platform that pairs embedded sensing with on-device intelligence, built to follow patients beyond the clinic.',
   'Calima pairs embedded sensing with on-device intelligence to follow patients beyond the walls of the clinic. The project covers the full stack — sensor hardware, real-time firmware and the models that turn raw signal into information a clinician can trust.',
   'In development', array['Embedded systems','Firmware','AI'], 10),
  ('opalina', 'Opalina', 'Clinical data, made legible',
   'A software platform that turns fragmented clinical data into clear, usable insight for the teams who act on it.',
   'Opalina is a software platform that turns fragmented clinical data into clear, usable insight. It began as a research question about how care teams actually make decisions — and grew into an exploration of what decision support should look like when it is designed around people, not dashboards.',
   'Applied research', array['Software','Clinical data','AI'], 20),
  ('orion', 'Órion', 'Instrumentation without compromise',
   'Instrumentation engineered for procedures where precision is non-negotiable — hardware, firmware and software designed as one.',
   'Órion is instrumentation for procedures where precision is non-negotiable. Hardware, firmware and software are engineered as a single system, with every layer designed, simulated and tested in-house.',
   'Prototype', array['Hardware','Instrumentation','Embedded systems'], 30),
  ('deriva', 'Deriva', 'Movement, measured',
   'Technology that reads human movement and turns it into objective measures for rehabilitation and follow-up.',
   'Deriva reads human movement and turns it into objective measures for rehabilitation and follow-up. Wearable sensing, signal processing and machine intelligence work together so that progress can be seen — not just felt.',
   'In development', array['Signal processing','Wearables','AI'], 40),
  ('nebula', 'Nebula', 'The connective layer',
   'Secure infrastructure that lets devices, software and people speak the same language across our ecosystem.',
   'Nebula is the connective layer of our ecosystem: the infrastructure that lets devices, software and people speak the same language. Quiet by design, it carries data securely from every other project to wherever it needs to be.',
   'Applied research', array['Software','Infrastructure','Interoperability'], 50)
) as seed(slug, nome, tagline, resumo, descricao, status, tags, ordem)
where not exists (select 1 from public.site_projetos);

-- ============================================================
-- FIM — SOMA 9.0
-- Depois desta migração:
--   1) publique a pasta site/ (index.html + admin.html);
--   2) edite os projetos em https://neurodynamics.dev/admin.html
--      com uma conta admin/pessoal do SOMA.
-- ============================================================
