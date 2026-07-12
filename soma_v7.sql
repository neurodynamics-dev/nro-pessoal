-- ============================================================
-- SOMA 7.0 — MIGRAÇÃO · NeuroDynamics
-- Papel dedicado "selecao": o módulo do Processo Seletivo
-- passa a viver DENTRO do SOMA · Gestão (index.html), visível
-- para quem tiver esse papel (além de admin/pessoal).
--
-- O acesso deixa de ser controlado pela tabela ps_comite (que
-- é removida) e passa a ser controlado pelo papel do perfil.
-- Para indicar alguém ao comitê: Seleção -> Configurações
-- (como admin), ou direto no banco:
--   update public.perfis set papel = 'selecao'
--    where email = 'membro@exemplo.com';
--
-- Pré-requisito: SOMA 6.0 aplicada.
-- Idempotente: pode rodar mais de uma vez sem duplicar nada.
-- COMO USAR: cole o arquivo INTEIRO no SQL Editor e Run.
-- ============================================================

-- ------------------------------------------------------------
-- 1. NOVO PAPEL "selecao" no check de perfis
--    admin   -> controle total (Diretoria)
--    pessoal -> controle total (Depto de Pessoal)
--    selecao -> consulta no SOMA + controle total do módulo
--               do Processo Seletivo (Comitê de Seleção)
--    leitura -> apenas consulta
-- ------------------------------------------------------------
alter table public.perfis drop constraint if exists perfis_papel_check;
alter table public.perfis add constraint perfis_papel_check
  check (papel in ('admin','pessoal','selecao','leitura'));

-- ------------------------------------------------------------
-- 2. eh_comite() passa a olhar somente o papel
--    (as políticas das tabelas ps_* já usam esta função,
--    então nada mais precisa mudar)
-- ------------------------------------------------------------
create or replace function public.eh_comite()
returns boolean language sql stable security definer
set search_path = public
as $$
  select public.papel_atual() in ('admin','pessoal','selecao');
$$;
grant execute on function public.eh_comite() to authenticated;

-- ------------------------------------------------------------
-- 3. MIGRA quem já estava em ps_comite para o novo papel e
--    remove a tabela (mecanismo antigo do soma-selecao.html).
--    Perfis admin/pessoal não são rebaixados.
-- ------------------------------------------------------------
do $$
begin
  if exists (select 1 from information_schema.tables
              where table_schema='public' and table_name='ps_comite') then
    update public.perfis p
       set papel = 'selecao'
      from public.ps_comite c
     where p.registro = c.registro
       and p.papel = 'leitura';
    drop table public.ps_comite;
  end if;
end $$;

-- ============================================================
-- FIM — SOMA 7.0
-- Depois desta migração:
--   1) publique o index.html atualizado (o soma-selecao.html
--      foi descontinuado e pode sair do ar);
--   2) confira os papéis: select email, papel from perfis;
-- ============================================================
