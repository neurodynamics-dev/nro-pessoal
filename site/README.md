# Site institucional — neurodynamics.dev

Site principal da NeuroDynamics, em inglês: home, **Who we are**, **Projects**
e **Contact**. Apresenta a equipe como uma iniciativa de pesquisa e
desenvolvimento em health-tech, nascida na Escola de Engenharia da UFMG e
sediada no LABBIO. Arquivo único (`index.html`), no mesmo padrão dos demais
apps do SOMA, com a base visual do site do processo seletivo (paleta, vidro,
fundo animado) em versão mais sóbria.

## Conteúdo

| Arquivo        | O que é |
|----------------|---------|
| `index.html`   | O site (rotas por hash: `#/`, `#/about`, `#/projects`, `#/contact`) |
| `admin.html`   | Painel para editar os projetos exibidos no site |
| `assets/`      | Logos locais usadas no letreiro de parceiros |
| `CNAME`        | Domínio do GitHub Pages (`neurodynamics.dev`) |

## Pré-requisitos

Aplicar a migração **`soma_v9.sql`** (na raiz deste repositório) no SQL
Editor do Supabase. Sem ela o site continua no ar com o conteúdo de reserva
(bloco `FALLBACK_PROJECTS` no topo do `<script>`), mas a edição pelo painel
fica indisponível.

## Como editar

- **Projetos (Calima, Opalina, Órion, Deriva, Nebula…):** em
  `https://<domínio>/admin.html`, com conta do SOMA de papel `admin` ou
  `pessoal`. Nome, tagline, resumo, descrição, status, tags, ordem, imagem
  e publicação. Os textos vão ao ar em inglês — preencha já em inglês.
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
- **Textos das páginas:** funções `pageHome/pageAbout/pageProjects/pageContact`
  no `<script>` de `index.html`.

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
