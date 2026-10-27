#!/usr/bin/env python3
"""Собирает игру в один самодостаточный HTML-файл (three.js, стили и скрипты внутри).

python3 party/tools/build.py            -> party/DuoParty.html
python3 party/tools/build.py --fragment  -> только содержимое страницы (для публикации как Artifact)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'src'


def inline(html: str) -> str:
    def css(m):
        return '<style>\n' + (SRC / m.group(1)).read_text(encoding='utf-8') + '\n</style>'

    def js(m):
        path = (SRC / m.group(1)).resolve()
        code = path.read_text(encoding='utf-8')
        if path.name == 'three.min.js':
            code = re.sub(r"^console\.warn\('Scripts[^\n]*?'\),", 'void 0,', code, count=1)
        if '</script' in code:
            code = code.replace('</script', '<\\/script')
        return '<script>\n' + code + '\n</script>'

    html = re.sub(r'<link rel="stylesheet" href="(style\.css)">', css, html)
    html = re.sub(r'<script src="([^"]+)"></script>', js, html)
    return html


def main():
    html = (SRC / 'index.html').read_text(encoding='utf-8')
    out = inline(html)
    if '--fragment' in sys.argv:
        head = re.search(r'<head>(.*?)</head>', out, re.S).group(1)
        body = re.search(r'<body>(.*)</body>', out, re.S).group(1)
        head = re.sub(r'<meta charset[^>]*>\s*', '', head)
        head = re.sub(r'<meta name="viewport"[^>]*>\s*', '', head)
        target = Path(sys.argv[sys.argv.index('--fragment') + 1]) if len(sys.argv) > sys.argv.index('--fragment') + 1 else ROOT / 'build' / 'fragment.html'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(head.strip() + '\n' + body.strip() + '\n', encoding='utf-8')
        print('fragment ->', target, round(target.stat().st_size / 1024), 'KB')
        return
    target = ROOT / 'DuoParty.html'
    target.write_text(out, encoding='utf-8')
    print('built ->', target, round(target.stat().st_size / 1024), 'KB')


if __name__ == '__main__':
    main()
