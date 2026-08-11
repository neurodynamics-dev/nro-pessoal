# Viagens — documentos de campo

Planos de viagem técnica em arquivo único, prontos para imprimir em A4 e levar
na pasta. Seguem o modelo de cabeçalho do `NRO-PUB-002 TEMPLATE DE DOCUMENTOS E
REGISTROS` e a linguagem visual de `brand.neurodynamics.dev`: Archivo para
títulos, IBM Plex Mono para rótulos técnicos, paleta oficial (Cortex, Axon,
Synapse) e o imagotipo servido deste próprio repositório.

## Conteúdo

| Arquivo | O que é |
|---|---|
| `NRO-PD-000-plano-viagem-sao-paulo.html` | Documento gerado, 23 páginas A4 — São Paulo, 11 a 14/08/2026 |
| `doc.template.html` | Fonte do documento: estrutura, estilos e conteúdo das guias |
| `build.py` | Gerador — embute fontes e imagotipo e resolve os campos sensíveis |

## Como gerar

```bash
python3 build.py --publico     # versão sem senhas (é a que fica versionada)
python3 build.py               # versão completa, para imprimir
```

O gerador baixa os subconjuntos latinos de Archivo e IBM Plex Mono do Google
Fonts, converte para `data:` URI e embute no HTML junto com os imagotipos de
`../mailer/`. O resultado é autossuficiente: abre e imprime sem rede, e serve
como página publicada sem depender de CDN. O cache fica em `.cache-fontes/`,
fora do versionamento.

## Dados sensíveis

Este repositório é **público** e serve GitHub Pages em
`pessoal.neurodynamics.dev`. Senhas de fechadura, localizador de reserva e
número de apartamento **não entram no versionamento** — nem no HTML gerado, nem
no `build.py`. Eles ficam em `dados.local.json`, que o `.gitignore` bloqueia:

```json
{
  "PNR": "XXXXXX",
  "APTO_CURTO": "apto ...",
  "COD_PREDIO": "<strong class=\"mono\" style=\"font-size:11pt\">0000</strong>",
  "...": "as demais chaves saem no erro do gerador"
}
```

Sem esse arquivo, `python3 build.py` sai com erro e lista as chaves esperadas;
`--publico` sempre funciona e produz linhas pontilhadas para preencher à mão.

Ao adaptar este documento para outra viagem, mantenha essa separação: qualquer
dado que dê acesso físico a um lugar ou a uma reserva só existe na versão
completa, que não é commitada.

## Estrutura do documento

Capa com sumário, e depois uma guia por assunto — cada uma começa em página
nova, com o cabeçalho NRO no topo e uma aba numerada na lateral, para achar a
seção folheando o impresso.

| Guia | Assunto |
|---|---|
| 01 | Resumo da missão — objetivo, equipe, endereços, janelas críticas |
| 02 | Cronograma hora a hora, de terça a sexta |
| 03 | Ida — voo, aeroporto e chegada |
| 04 | Hospedagem e acessos |
| 05 | Ensaio na FMUSP — local, contato, simulador e roteiro |
| 06 | Checklist técnico e de bagagem |
| 07 | Rotas e deslocamentos, com alternativas por trecho |
| 08 | Clima e vestuário |
| 09 | Alimentação |
| 10 | Volta — Plano A (aéreo) e Plano B (rodoviário) |
| 11 | Contingências |
| 12 | Contatos úteis |
| 13 | Custos estimados |
| 14 | Anotações de campo |

## Como editar

- **Conteúdo e guias:** blocos `<section class="sheet">` do `doc.template.html`.
  Cada folha tem `{{HD:Nome da seção}}` no topo e `{{PE}}` no rodapé.
- **Metadados** (código, revisão, departamento, título, período): topo do `build.py`.
- **Estilos:** bloco `<style>` no início do template. Os tokens da marca estão
  em `:root` e não devem ser alterados.

Uma folha precisa caber em **1119 px** (296 mm) de altura para não vazar para a
página seguinte. Ao acrescentar conteúdo, confira a paginação antes de imprimir:
o navegador não avisa, apenas quebra. Quando uma guia não couber, divida em uma
folha de continuação em vez de reduzir a fonte.

## Impressão

A4, sem escala ("tamanho real" ou 100%), com impressão de cores e imagens de
fundo ativada — as bandas verdes e as abas numeradas dependem disso. As margens
já estão no documento; deixe as do navegador em zero.
