#!/usr/bin/env python3
"""
Gera o documento de viagem a partir de `doc.template.html`.

Embute no HTML as fontes da marca (Archivo e IBM Plex Mono) e o imagotipo, de
modo que o arquivo final seja autossuficiente: abre e imprime sem rede, e
funciona como página publicada sem depender de CDN.

Uso:
    python3 build.py                      # versão completa, com os dados da reserva
    python3 build.py --publico            # versão sem senhas, para versionar
    python3 build.py --publico saida.html # define o arquivo de saída

O modo --publico existe porque este repositório é público e serve GitHub Pages
em pessoal.neurodynamics.dev: senhas de fechadura, localizador da reserva e
número do apartamento não podem ser versionados. Na versão pública esses campos
viram linhas pontilhadas para preencher à mão antes de imprimir.
"""
import base64
import json
import os
import re
import sys
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(BASE)
CACHE = os.path.join(BASE, '.cache-fontes')

FONTES_URL = ('https://fonts.googleapis.com/css2'
              '?family=Archivo:wght@500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap')
UA = ('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')

# Imagotipos servidos deste mesmo repositório (pasta mailer/), nas cores da marca:
# Blackout para impressos e fundos claros, branco para a capa escura.
LOGOS = {
    'LOGO_DARK':  os.path.join(REPO, 'mailer', 'logo-1d1d1f.png'),
    'LOGO_WHITE': os.path.join(REPO, 'mailer', 'logo-ffffff.png'),
}

# ---------------------------------------------------------------- metadados
CODIGO = 'NRO-PD-000'
REV = 'Rev. A'
DEP = 'Departamento de Pesquisa e Desenvolvimento'
TITULO = 'Plano de Viagem Técnica — São Paulo · Ensaio ASL 5000'
PERIODO = '11 a 14 de agosto de 2026 · São Paulo'

# --------------------------------------------------------- dados sensíveis
# Os valores reais NÃO ficam neste arquivo. Eles moram em `dados.local.json`,
# que o .gitignore mantém fora do versionamento. Sem esse arquivo, o gerador
# produz a versão pública, com linhas pontilhadas no lugar dos campos.
LOCAL = os.path.join(BASE, 'dados.local.json')
CAMPO = '<span class="campo" style="min-width:26mm"></span>'
PUBLICO = {
    'PNR':           CAMPO,
    'APTO_CURTO':    'apto ' + CAMPO,
    'UNIDADE_LONGA': 'andar e apartamento ' + CAMPO,
    'UNIDADE_TAB':   'andar e apartamento: ' + CAMPO,
    'COD_PREDIO':    CAMPO,
    'COD_APTO':      CAMPO,
    'COD_LINHA':     'Preencher as senhas do Guia 04.',
    'ROT_CODIGOS':   'Códigos de acesso — preencher à mão antes de imprimir',
}


def dados_sensiveis(modo):
    """Devolve os campos sensíveis: reais no modo completo, em branco no público."""
    if modo == 'publico':
        return PUBLICO
    if not os.path.exists(LOCAL):
        sys.exit(f'{os.path.basename(LOCAL)} não encontrado — crie-o com as chaves '
                 f'{sorted(PUBLICO)} ou rode com --publico.')
    reais = json.load(open(LOCAL, encoding='utf-8'))
    faltando = sorted(set(PUBLICO) - set(reais))
    if faltando:
        sys.exit('faltam chaves em %s: %s' % (os.path.basename(LOCAL), faltando))
    return reais


def baixa(url, destino=None):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        dados = r.read()
    if destino:
        open(destino, 'wb').write(dados)
    return dados


def css_das_fontes():
    """Baixa os subconjuntos latinos das fontes da marca e devolve @font-face em data: URI."""
    os.makedirs(CACHE, exist_ok=True)
    bruto = os.path.join(CACHE, 'google-fonts.css')
    if not os.path.exists(bruto):
        baixa(FONTES_URL, bruto)
    css = open(bruto, encoding='utf-8').read()

    saida = []
    for subset, bloco in re.findall(r'/\*\s*([\w-]+)\s*\*/\s*(@font-face\s*\{.*?\})', css, re.S):
        if subset not in ('latin', 'latin-ext'):
            continue                      # o documento é em português; o resto é peso morto
        url = re.search(r'url\((https://[^)]+\.woff2)\)', bloco).group(1)
        arq = os.path.join(CACHE, url.rsplit('/', 1)[-1])
        if not os.path.exists(arq):
            baixa(url, arq)
        b64 = base64.b64encode(open(arq, 'rb').read()).decode()
        fam = re.search(r"font-family:\s*'([^']+)'", bloco).group(1)
        peso = re.search(r'font-weight:\s*(\d+)', bloco).group(1)
        faixa = re.search(r'unicode-range:\s*([^;]+);', bloco).group(1).strip()
        saida.append(
            f"@font-face{{font-family:'{fam}';font-style:normal;font-weight:{peso};"
            f"font-stretch:100%;font-display:swap;"
            f"src:url(data:font/woff2;base64,{b64}) format('woff2');unicode-range:{faixa}}}")
    if not saida:
        sys.exit('nenhuma fonte extraída — o CSS do Google Fonts mudou de formato?')
    return '\n'.join(saida)


def main():
    modo = 'publico' if '--publico' in sys.argv else 'completo'
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    destino = args[0] if args else os.path.join(BASE, 'NRO-PD-000-plano-viagem-sao-paulo.html')

    tpl = open(os.path.join(BASE, 'doc.template.html'), encoding='utf-8').read()

    cabecalho = (
        '<div class="nro-hd">'
        '<div class="marca"><img src="{{LOGO_DARK}}" alt="NeuroDynamics"></div>'
        '<div class="meio">'
        f'<div class="dep">{DEP}</div>'
        f'<div class="tit">{TITULO} · <span class="dim">{{SECAO}}</span></div>'
        '</div>'
        f'<div class="cod"><b>{CODIGO}</b><span>{REV}</span></div>'
        '</div>'
    )
    rodape = ('<div class="pe">'
              f'<span>{CODIGO} {REV} · NeuroDynamics · uso interno</span>'
              f'<span>{PERIODO}</span>'
              '</div>')

    tpl = re.sub(r'\{\{HD:([^}]+)\}\}', lambda m: cabecalho.replace('{SECAO}', m.group(1)), tpl)
    tpl = tpl.replace('{{PE}}', rodape)
    tpl = tpl.replace('{{FONT_CSS}}', css_das_fontes())

    for nome, caminho in LOGOS.items():
        b64 = base64.b64encode(open(caminho, 'rb').read()).decode()
        tpl = tpl.replace('{{%s}}' % nome, 'data:image/png;base64,' + b64)
    for nome, valor in dados_sensiveis(modo).items():
        tpl = tpl.replace('{{%s}}' % nome, valor)

    sobrou = re.findall(r'\{\{[A-Z_]+\}\}|\{(?:LOGO_[A-Z]+|SECAO)\}', tpl)
    if sobrou:
        sys.exit('placeholders não resolvidos: %s' % sorted(set(sobrou)))

    corpo = tpl.split('</style>', 1)
    completo = (
        '<!DOCTYPE html>\n<html lang="pt-BR">\n<head>\n'
        '<meta charset="UTF-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        '<meta name="description" content="Plano de viagem técnica da NeuroDynamics a São Paulo, '
        '11 a 14 de agosto de 2026: ensaio do sistema de eletroestimulação diafragmática com o '
        'simulador ASL 5000 na FMUSP.">\n'
        '<meta name="theme-color" content="#00352F">\n'
        + corpo[0] + '</style>\n</head>\n<body>' + corpo[1] + '\n</body>\n</html>\n'
    )
    open(destino, 'w', encoding='utf-8').write(completo)
    print(f'modo {modo} → {destino} ({os.path.getsize(destino) // 1024} KB)')


if __name__ == '__main__':
    main()
