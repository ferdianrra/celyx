"""Rebuild the generated files after you change anything.

    python3 tools/build.py

Sources you edit:   shader/environment.frag.glsl, web/env.js, web/index.html, data/stars.json, data/milky-way-radec-4096.jpg
Generated (don't edit by hand): web/shader.js, web/stars.js, web/assets/milky-way-radec.jpg, night-sea-preview.html
"""
import base64, json, os, re, shutil
K = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
p = lambda *a: os.path.join(K, *a)
rd = lambda *a: open(p(*a), encoding='utf-8').read()
frag = rd('shader', 'environment.frag.glsl')
assert '`' not in frag and '${' not in frag, 'the shader is embedded in a JS template string: no backticks or ${'
stars = json.loads(rd('data', 'stars.json'))
stars_js = ('/* generated from data/stars.json. HYG v3.8 (CC BY-SA 4.0): [raHours, decDeg, magnitude, colourIndexBV, name] */\n'
            'window.STARS=' + json.dumps(stars, separators=(',', ':'), ensure_ascii=False) + ';\n')
frag_js = '/* generated from shader/environment.frag.glsl */\nwindow.FRAG=`' + frag + '`;\n'
open(p('web', 'stars.js'), 'w', encoding='utf-8').write(stars_js)
open(p('web', 'shader.js'), 'w', encoding='utf-8').write(frag_js)
os.makedirs(p('web', 'assets'), exist_ok=True)
shutil.copy(p('data', 'milky-way-radec-4096.jpg'), p('web', 'assets', 'milky-way-radec.jpg'))
# one self-contained file: same page, with every script and the image inlined
html = rd('web', 'index.html')
mw = 'data:image/jpeg;base64,' + base64.b64encode(open(p('data', 'milky-way-radec-4096.jpg'), 'rb').read()).decode()
inline = {'stars.js': stars_js, 'shader.js': frag_js, 'env.js': rd('web', 'env.js')}
for name, code in inline.items():
    tag = '<script src="%s"></script>' % name
    assert html.count(tag) == 1, tag
    html = html.replace(tag, '<script>\n' + code + '</script>')
html, n = re.subn(r'window\.MW_SRC="[^"]*"', lambda m: 'window.MW_SRC="' + mw + '"', html)
assert n == 1
open(p('night-sea-preview.html'), 'w', encoding='utf-8').write(html)
print('ok: web/ refreshed, night-sea-preview.html', round(len(html) / 1e6, 2), 'MB')
