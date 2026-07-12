# Site do Processo Seletivo — selecao.neurodynamics.dev

Site público do PS da NeuroDynamics: divulgação, cronograma, edital e
resultados, inscrição sem login e agendamento das dinâmicas/entrevistas.
Arquivo único (`index.html`), no mesmo padrão dos demais apps do SOMA.

## Pré-requisitos

Aplicar as migrações **`soma_v6.sql`** e **`soma_v7.sql`** (na raiz deste
repositório) no SQL Editor do Supabase. Sem elas o site continua no ar com
o conteúdo de reserva (cronograma fixo), mas inscrição/acompanhamento
ficam indisponíveis.

A página "A NeuroDynamics" (textos, fotos e vídeo) é editada no bloco
`SOBRE`, no topo do `<script>` de `index.html`.

## Como publicar

O GitHub Pages atende **um domínio por repositório** — e este repositório
já usa `pessoal.neurodynamics.dev`. Duas opções:

1. **Repositório próprio (recomendado):** crie `neurodynamics-dev/nro-selecao`,
   copie `index.html` e `CNAME` desta pasta para a raiz, ative o Pages
   (branch `main`) e crie o CNAME `selecao` → `neurodynamics-dev.github.io`
   no Cloudflare.
2. **Cloudflare Pages:** aponte um projeto para este repositório com
   "build output directory" = `selecao/` e o domínio customizado
   `selecao.neurodynamics.dev`.

## Segurança

O site usa apenas a chave `anon` do Supabase e conversa com o banco
exclusivamente pelas funções `security definer` da migração
(`ps_site`, `ps_inscrever`, `ps_acompanhar`, `ps_horarios`, `ps_agendar`).
Nenhuma tabela do módulo tem política de leitura/escrita para `anon`;
o candidato se identifica por **protocolo + e-mail**, sem senha.
O controle do processo é feito pelo Comitê de Seleção na página
**Seleção** do SOMA · Gestão (papel `selecao` no banco).
