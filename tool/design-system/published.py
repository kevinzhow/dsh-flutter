"""Read published bundle CSS without executing JavaScript."""
from pathlib import Path
import argparse,base64,hashlib,json,re,tarfile

def menu_portal_snapshot(archive):
    with tarfile.open(archive) as tar:
        bundle = tar.extractfile('package/lib/index.js').read()
    text = bundle.decode()
    start = text.index('function Menu(')
    match = re.search(r'const MARGIN = .*?if \(lh > 0\) y = [^;]+;', text[start:], re.S)
    if match is None: raise ValueError('published menu portal placement is not recognized')
    return {'bundleSha256': hashlib.sha256(bundle).hexdigest(), 'placement': match[0]}

def tooltip_placement_snapshot(archive):
    with tarfile.open(archive) as tar:
        bundle = tar.extractfile('package/lib/index.js').read()
    text = bundle.decode()
    start = text.index('function Tooltip(')
    patterns = {
        'signature': r'function Tooltip\([^\n]+',
        'anchor': r'setPos\(\{\s*x: side === "right".*?\}\);',
        'fit': r'const edgeMargin = .*?el\.style\.visibility = "visible";',
    }
    snippets = {}
    for name, pattern in patterns.items():
        match = re.search(pattern, text[start:], re.S)
        if match is None: raise ValueError('published tooltip placement is not recognized: ' + name)
        snippets[name] = ' '.join(match[0].split())
    return {'bundleSha256': hashlib.sha256(bundle).hexdigest(), **snippets}

def plugin_style_snapshot(archive):
    with tarfile.open(archive) as tar:
        bundle=tar.extractfile('package/lib/client.js').read()
        text=bundle.decode()
        start=text.index('PluginManagerPage.module.css.mjs')
        literal=re.search(r'const css = ("(?:\\.|[^"\\])*");',text[start:])
        if literal is None:raise ValueError('published CSS JSON literal not recognized')
        css=json.loads(literal.group(1))
        prefix='var PluginManagerPage_module_css_default = '
        start=text.index(prefix)+len(prefix)
        classes,_=json.JSONDecoder().raw_decode(text[start:])
        if not isinstance(classes,dict) or not all(isinstance(k,str) and isinstance(v,str) for k,v in classes.items()):
            raise ValueError('published CSS class export is not a static string map')
        return {'css':css,'classes':classes,'bundleSha256':hashlib.sha256(bundle).hexdigest(),
                'manifest':tar.extractfile('package/package.json').read(),'license':tar.extractfile('package/LICENSE').read()}

def unhash_selectors(text,classes):
    inverse={value:key for key,value in classes.items()}
    return re.sub(r'\.([A-Za-z_][\w-]*)',lambda m:'.'+inverse.get(m[1],m[1]),text)

THEME_SHEETS = ('base', 'corner_shape', 'design_platform', 'focus', 'onboarding', 'scrollbar', 'gradient_shadow_text', 'shiki')

def theme_injection_order(text):
    arrays = re.findall(r'const STYLES = \[(.*?)\];', text, re.S)
    if len(arrays) != 1: raise ValueError('published theme injection array missing/ambiguous')
    pair = r'\["([\w.-]+\.css)",\s*(\w+)_css_default\]'
    entries = re.findall(pair, arrays[0])
    # Static pairs separated by one comma; no holes or expressions.
    if not re.fullmatch(r'\s*' + pair + r'(?:\s*,\s*' + pair + r')*\s*,?\s*', arrays[0]):
        raise ValueError('unrecognized published theme injection syntax')
    expected = [(name.replace('_', '-') + '.css', name) for name in THEME_SHEETS]
    if entries != expected: raise ValueError('published theme injection order requires classification')
    return [name for name, _ in entries]

def theme_style_snapshot(archive):
    with tarfile.open(archive) as tar:
        bundle = tar.extractfile('package/lib/client.js').read()
        css = {}
        for name in THEME_SHEETS:
            literals = re.findall(r'var ' + name + r'_css_default = ("(?:\\.|[^"\\])*");', bundle.decode())
            if len(literals) != 1: raise ValueError('published theme CSS literal missing/ambiguous: ' + name)
            css[name.replace('_', '-') + '.css'] = json.loads(literals[0])
        exported = re.findall(r'var (\w+)_css_default = \"', bundle.decode())
        if tuple(exported) != THEME_SHEETS: raise ValueError('published theme stylesheet set/order requires classification')
        return {'css': css, 'order': theme_injection_order(bundle.decode()), 'bundleSha256': hashlib.sha256(bundle).hexdigest(),
                'manifest': tar.extractfile('package/package.json').read(), 'license': tar.extractfile('package/LICENSE').read()}

def terminal_font_snapshot(archive):
    with tarfile.open(archive) as tar:
        bundle = tar.extractfile('package/lib/client.terminal.js').read()
        literals = re.findall(r'const TERMINAL_FONT_STACK = ("(?:\\.|[^"\\])*");', bundle.decode())
        if len(literals) != 1: raise ValueError('published terminal font literal missing/ambiguous')
        return {'font': json.loads(literals[0]), 'bundleSha256': hashlib.sha256(bundle).hexdigest(),
                'manifest': tar.extractfile('package/package.json').read(), 'license': tar.extractfile('package/LICENSE').read()}

def verify_packages(source=None):
    here = Path(__file__).resolve().parent
    lock = json.loads((here / 'sources.lock.json').read_text())
    for package in lock['packages']:
        folder = here / 'upstream' / package['snapshotFolder']
        for name, sha in package['files'].items():
            if hashlib.sha256((folder / name).read_bytes()).hexdigest() != sha:
                raise ValueError('published snapshot hash mismatch: ' + package['name'] + '/' + name)
        manifest = json.loads((folder / 'package.json').read_text())
        if (manifest['name'], manifest['version']) != (package['name'], package['version']):
            raise ValueError('published package identity mismatch')
        if source is not None:
            current = json.loads((source / package['sourcePackage']).read_text())
            consumer = json.loads((source / package['referenceConsumer']).read_text())
            if current['version'] != package['version']:
                raise ValueError('reference dependency version drift: regenerate from its published package')
            if consumer[package['dependencyField']].get(package['name']) != package['dependencySpecifier']:
                raise ValueError('reference dependency specifier drift: update the package lock')
            for name, sha in package.get('referenceSourceSha256', {}).items():
                if hashlib.sha256((source / name).read_bytes()).hexdigest() != sha:
                    raise ValueError('reference source drift: review the corresponding published package: ' + name)
    return lock

def verify_snapshot(archive, package, folder):
    integrity = 'sha512-' + base64.b64encode(hashlib.sha512(Path(archive).read_bytes()).digest()).decode()
    if integrity != package['integrity']: raise ValueError('published archive integrity mismatch')
    kind = package.get('extractionKind', 'plugin-css')
    if kind == 'plain-files':
        with tarfile.open(archive) as tar:
            for name, member in package['archiveFiles'].items():
                if (folder / name).read_bytes() != tar.extractfile(member).read():
                    raise ValueError('published plain-file snapshot mismatch: ' + name)
        return
    if kind == 'primitive-css':
        with tarfile.open(archive) as tar:
            for name in package['files']:
                if name == 'menu-portal.json':
                    if json.loads((folder / name).read_text()) != menu_portal_snapshot(archive):
                        raise ValueError('published menu portal snapshot mismatch')
                    continue
                if name == 'tooltip-placement.json':
                    if json.loads((folder / name).read_text()) != tooltip_placement_snapshot(archive):
                        raise ValueError('published tooltip placement snapshot mismatch')
                    continue
                member = 'package/' + ('' if name in ('package.json', 'LICENSE') else 'lib/') + name
                if (folder / name).read_bytes() != tar.extractfile(member).read():
                    raise ValueError('published primitive snapshot mismatch: ' + name)
        return
    extract = {'plugin-css': plugin_style_snapshot, 'theme-css': theme_style_snapshot, 'terminal-font': terminal_font_snapshot}
    result = extract[kind](archive)
    if result['bundleSha256'] != package['publishedBundleSha256']: raise ValueError('published bundle hash mismatch')
    if kind == 'plugin-css':
        if (folder / 'PluginManagerPage.module.css').read_text() != result['css']: raise ValueError('decoded CSS snapshot mismatch')
        if json.loads((folder / 'classes.json').read_text()) != result['classes']: raise ValueError('class export snapshot mismatch')
    elif kind == 'theme-css':
        for name, css in result['css'].items():
            if (folder / name).read_text() != css: raise ValueError('decoded theme CSS snapshot mismatch: ' + name)
        if json.loads((folder / 'styles-order.json').read_text()) != result['order']:
            raise ValueError('published theme injection order snapshot mismatch')
    else:
        if json.loads((folder / 'terminal-font.json').read_text()) != {'terminalFontStack': result['font']}:
            raise ValueError('decoded terminal font snapshot mismatch')
    for key, name in [('manifest', 'package.json'), ('license', 'LICENSE')]:
        if (folder / name).read_bytes() != result[key]: raise ValueError('package metadata snapshot mismatch')

def main():
    parser = argparse.ArgumentParser(description='Verify reproducible inputs from a locked published package archive (no JS execution).')
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--package', default='@deepseek-ai/dsh-client-ui-plugin-manager')
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    package = next(p for p in json.loads((here / 'sources.lock.json').read_text())['packages'] if p['name'] == args.package)
    verify_snapshot(args.archive, package, here / 'upstream' / package['snapshotFolder'])
    print('design-system: published archive integrity and decoded input snapshots agree')

if __name__ == '__main__': main()
