# nro-pessoal — encaminhamento e acervo

Este repositório **não é mais um app**. O SOMA · Gestão foi unificado com o
Portal do Membro: hoje tudo mora em
[membro.neurodynamics.dev](https://membro.neurodynamics.dev) — um endereço, um
login, uma navegação. O plano e o porquê estão em
[`membro/PLANO-UNIFICACAO.md`](https://github.com/neurodynamics-dev/membro/blob/main/PLANO-UNIFICACAO.md).

O domínio `pessoal.neurodynamics.dev` continua no ar por três motivos, e só
por eles.

## 1. Encaminhar quem chega por link ou favorito antigo

| Arquivo | Leva para |
|---|---|
| `index.html` | o portal, com um resumo de onde cada coisa foi parar |
| `app.html` | a Agenda — e repassa o token do QR antigo da entrada, para o check-in continuar sendo registrado |
| `quiosque.html` | o quiosque, que agora é servido pelo portal |

## 2. Servir as imagens dos e-mails já enviados

A pasta [`mailer/`](mailer/) tem os ícones e as logos recoloridas que o Full
mailer usa. Ela **também** existe no repositório `membro`, que é de onde os
e-mails novos passam a puxar — mas os que já foram enviados apontam para
`pessoal.neurodynamics.dev/mailer/`, e não dá para reescrever a caixa de
entrada de ninguém. **Não apague esta pasta.**

## 3. Guardar as fotos do quadro

A pasta [`fotos/`](fotos/) é a fonte viva das fotos de perfil do quadro —
confirmado no código, não por suposição. A regra, em `membro/index.html`:

1. se o membro tem `membros.foto_url` preenchido, vale esse endereço;
2. **senão**, o portal monta `fotos/<registro>.<ext>` daqui e tenta as
   extensões em cascata até uma carregar;
3. se nenhuma carregar, aparecem as iniciais do nome.

Ou seja: hoje quase todo mundo cai no passo 2, e esta pasta é o acervo. O
portal a busca por `raw.githubusercontent.com`, que não depende do GitHub
Pages — então ela sobrevive a qualquer mudança de domínio. **Não apague.**

Para migrar uma foto para outro lugar, basta preencher `foto_url` na ficha do
membro (SOMA → Equipe → ficha → Dados): o passo 1 passa na frente e o arquivo
daqui deixa de ser consultado para aquela pessoa.

## O app antigo

O SOMA · Gestão está preservado em [`soma-legado.html`](soma-legado.html), sem
link e sem ser servido como página inicial. É rede de segurança para a virada:
se algo faltar no portal, um `git mv` o recoloca no ar em um minuto.

Quando a equipe estiver confortável — um mês de uso é uma boa régua —, este
arquivo pode ser apagado. O histórico do git continua guardando tudo.

Por um tempo, ele foi mais que rede de segurança: o **Processo Seletivo** e
os **OKRs** ficaram de fora da migração e só existiam aqui, até ganharem
`#/selecao` e `#/okrs` no portal. O mês de uso conta a partir de quando
eles chegaram, não do corte.

## As migrações

`soma_v6.sql` a `soma_v13.sql` continuam aqui como acervo. As versões
renomeadas, sem a colisão de numeração que existia entre os dois repositórios,
estão em [`membro/db/aplicadas/`](https://github.com/neurodynamics-dev/membro/tree/main/db/aplicadas)
— é lá que a linha de migrações continua.
