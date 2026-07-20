# Imagens do full mailer

PNGs referenciados **por link** nos e-mails gerados em SOMA → Relatórios →
Full mailer (`https://pessoal.neurodynamics.dev/mailer/…`, servidos pelo
GitHub Pages deste repositório). Nada é embutido no HTML do e-mail: imagem
em data-URI vira anexo do documento nos clientes de e-mail — ou é descartada.

## Arquivos

- `logo-<cor>.png` — imagotipo NeuroDynamics recolorido, 564 px de largura
  (3× dos 188 px exibidos). Uma variante por cor `logo` dos temas
  (`THEMES_MAILER` no index.html): `00594f`, `0f7c8a`, `8a6d1f`, `cedc00`,
  `5c7a00`, `ffffff`, `1d1d1f`.
- `ico-<rede>-<cor>.png` — ícones sociais (site, instagram, linkedin,
  youtube, x, facebook), 63 px (3× dos 21 px exibidos). Uma variante por cor
  `bodyAccent` dos temas: `00594f`, `0f7c8a`, `7a5e15`, `5c7a00`, `1d1d1f`.

`<cor>` é o hex minúsculo sem `#`.

## Ao criar um tema novo

Se o tema usar uma cor `logo` ou `bodyAccent` que ainda não tem arquivo aqui,
gere as variantes que faltam (senão a imagem quebra no e-mail):

1. logo: recolorir os pixels opacos do
   [imagotipo preto](https://raw.githubusercontent.com/matheusmarcondes1/nro/refs/heads/main/imagotipo%20preto.png)
   para a nova cor (preservando o alfa) e redimensionar para 564 px de largura;
2. ícones: rasterizar os SVGs de 24×24 usados no `_socialImg`/histórico do
   repositório com `fill` na nova cor, em 63×63;
3. salvar aqui seguindo a nomenclatura acima e fazer o merge — o GitHub Pages
   publica junto com o site.
