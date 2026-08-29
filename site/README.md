# Site institucional — neurodynamics.dev

Site principal da NeuroDynamics em **três idiomas** (inglês, português e
francês, com seletor no cabeçalho): home, **Quem somos**, **Projetos** e
**Contato**. Apresenta a equipe como uma **organização sem fins lucrativos**
de pesquisa e desenvolvimento em health-tech, nascida na Escola de Engenharia
da UFMG e sediada no LABBIO. Arquivo único (`index.html`), no mesmo padrão dos
demais apps do SOMA, com a base visual do site do processo seletivo (paleta,
vidro, fundo animado) em versão mais sóbria.

## Conteúdo

| Arquivo        | O que é |
|----------------|---------|
| `index.html`   | O site (rotas por hash: `#/`, `#/about`, `#/projects`, `#/contact`) |
| `admin.html`   | Painel para editar os projetos exibidos no site |
| `assets/`      | Logos locais usadas no letreiro de parceiros |
| `CNAME`        | Domínio do GitHub Pages (`neurodynamics.dev`) |

## Pré-requisitos

Aplicar as migrações **`soma_v9.sql`** (tabela dos projetos) e
**`soma_v13.sql`** (colunas de tradução) no SQL Editor do Supabase. Sem elas
o site continua no ar com o conteúdo de reserva (bloco `FALLBACK_PROJECTS` no
topo do `<script>`), mas a edição pelo painel fica indisponível.

> Ao colar SQL no Supabase, atenção ao travessão (—): em alguns caminhos de
> cópia ele vira `--`, comenta o resto da linha e quebra a migração. Foi o
> que aconteceu na primeira tentativa da `soma_v9.sql`. As migrações novas
> evitam travessão dentro de strings; acentos são seguros.

## Os três idiomas

O site é publicado em inglês, português e francês. O seletor fica no canto
superior direito do cabeçalho flutuante; a escolha é lembrada no navegador
(`localStorage`) e pode ser forçada por link com `?lang=pt` ou `?lang=fr`.
Sem escolha prévia, o site segue o idioma do navegador e cai no inglês.

- **Textos das páginas:** bloco `L` no topo do `<script>` de `index.html`,
  com um objeto por idioma (`en`, `pt`, `fr`). É o único lugar a editar.
- **Textos dos projetos:** no banco, em colunas por idioma — o inglês nas
  colunas originais (`tagline`, `resumo`, `descricao`) e as traduções com
  sufixo (`_pt`, `_fr`). O que ficar vazio em PT/FR cai no inglês.
- **Status e tags:** guardados uma única vez, em inglês, e traduzidos pelo
  site por dicionário (`status` e `tags` dentro de cada idioma no bloco `L`).
  Ao criar um status ou tag novo, acrescente a tradução lá.

## Como editar

- **Projetos (Calima, Opalina, Órion, Deriva, Nebula…):** em
  `https://<domínio>/admin.html`, com conta do SOMA de papel `admin` ou
  `pessoal`. Nome, tagline, resumo, descrição, status, tags, ordem, imagem
  e publicação. Os campos de texto têm **abas EN / PT / FR**; o que ficar
  vazio em português ou francês cai no texto em inglês.
  Enquanto `imagem_url` estiver vazia o site mostra o placeholder técnico;
  ao subir as imagens definitivas, basta colar a URL.
- **Parceiros do letreiro:** bloco `PARTNERS` no topo do `<script>` de
  `index.html`. Itens com `img` usam o arquivo (coloque em `assets/`);
  sem `img`, o site desenha uma marca tipográfica monocromática — troque
  pela logo real quando o arquivo existir (UFMG e Escola de Engenharia
  estão tipográficas por enquanto).
- **E-mail de contato:** constante `CONTACT_EMAIL` no mesmo bloco.
  **Confirme que a caixa `contato@neurodynamics.dev` existe** (ou troque
  pelo endereço certo) antes de divulgar o site.
- **Estrutura das páginas:** funções `pageHome/pageAbout/pageProjects/pageContact`
  no `<script>` de `index.html` (elas só montam o HTML; o texto vem do bloco `L`).

## Como publicar

O GitHub Pages atende **um domínio por repositório** — e este repositório
já usa `pessoal.neurodynamics.dev`. Duas opções (mesmo esquema do site do
processo seletivo):

1. **Repositório próprio (recomendado):** crie `neurodynamics-dev/nro-site`,
   copie o conteúdo desta pasta para a raiz, ative o Pages (branch `main`)
   e aponte o apex `neurodynamics.dev` → GitHub Pages no Cloudflare
   (registros `A`/`AAAA` do Pages, ou `CNAME` achatado para
   `neurodynamics-dev.github.io`).
2. **Cloudflare Pages:** aponte um projeto para este repositório com
   "build output directory" = `site/` e o domínio customizado
   `neurodynamics.dev`.

## Segurança

O site usa apenas a chave `anon` do Supabase e lê o banco exclusivamente
pela função `security definer` da migração (`site_projetos_publico`), que
devolve só projetos publicados. A tabela `site_projetos` não tem política
para `anon`; a escrita exige login (contas do SOMA) e papel `admin` ou
`pessoal` — o `admin.html` é só interface, a regra mora no banco.
