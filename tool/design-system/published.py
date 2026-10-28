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

def market_style_snapshot(archive):
    with tarfile.open(archive) as tar:
        bundle = tar.extractfile('package/lib/client.js').read()
        text = bundle.decode()
        start = text.index('DiscoverSection.module.css.mjs')
        literal = re.search(r'const css = ("(?:\\.|[^"\\])*");', text[start:])
        if literal is None: raise ValueError('published market CSS JSON literal not recognized')
        css = json.loads(literal.group(1))
        prefix = 'var DiscoverSection_module_css_default = '
        start = text.index(prefix) + len(prefix)
        classes, _ = json.JSONDecoder().raw_decode(text[start:])
        if not isinstance(classes, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in classes.items()):
            raise ValueError('published market CSS class export is not a static string map')
        return {'css': css, 'classes': classes, 'bundleSha256': hashlib.sha256(bundle).hexdigest(),
                'manifest': tar.extractfile('package/package.json').read(), 'license': tar.extractfile('package/LICENSE').read()}

def bundle_region(text, name):
    """Return one named release region; never execute its JavaScript."""
    matches = list(re.finditer(r'//#region ([^\r\n]+)', text))
    starts = [m for m in matches if m[1] == name or m[1].endswith('/' + name)]
    if len(starts) != 1:
        raise ValueError('published bundle region missing/ambiguous: ' + name)
    start = starts[0].start()
    end = text.find('//#endregion', starts[0].end())
    if end < 0:
        raise ValueError('published bundle region has no end: ' + name)
    return text[start:end]

def agent_preset_style_snapshot(archive):
    with tarfile.open(archive) as tar:
        bundle = tar.extractfile('package/lib/client.js').read()
        text = bundle.decode()
        styles, classes = {}, {}
        for component, filename in [('PresetGuideDialog', 'PresetGuideDialog.module.css'),
                                     ('AgentPresetSection', 'styles.css')]:
            region = bundle_region(text, component + '.module.css.mjs')
            # The guide variable is css$1, while the roster variable is css.
            # Searching only `const css =` silently skips to another module.
            literals = re.findall(r'\bconst css(?:\$\d+)? = ("(?:\\.|[^"\\])*");', region)
            if len(literals) != 1:
                raise ValueError('published preset CSS literal missing/ambiguous: ' + component)
            styles[filename] = json.loads(literals[0])
            prefix = 'var ' + component + '_module_css_default = '
            if region.count(prefix) != 1:
                raise ValueError('published preset class export missing/ambiguous: ' + component)
            mapping, _ = json.JSONDecoder().raw_decode(region.split(prefix, 1)[1])
            if not isinstance(mapping, dict) or not mapping or not all(isinstance(k, str) and isinstance(v, str) for k, v in mapping.items()):
                raise ValueError('published preset class export is not a static string map')
            classes['guide' if component == 'PresetGuideDialog' else 'roster'] = mapping
        return {'css': styles, 'classes': classes, 'bundleSha256': hashlib.sha256(bundle).hexdigest(),
                'readerBehavior': {'bundleSha256': hashlib.sha256(bundle).hexdigest(),
                                   'region': bundle_region(text, 'PresetGuideDialog.js')},
                'manifest': tar.extractfile('package/package.json').read(),
                'license': tar.extractfile('package/LICENSE').read()}

def modal_layer_snapshot(archive):
    with tarfile.open(archive) as tar:
        bundle = tar.extractfile('package/lib/index.js').read()
    text = bundle.decode()
    return {'bundleSha256': hashlib.sha256(bundle).hexdigest(),
            'layer': bundle_region(text, 'useModalLayer.js'),
            'modal': bundle_region(text, 'Modal.js'),
            'risk': bundle_region(text, 'RiskConfirmation.js')}

def unhash_selectors(text,classes):
    inverse={value:key for key,value in classes.items()}
    return re.sub(r'\.([A-Za-z_][\w-]*)',lambda m:'.'+inverse.get(m[1],m[1]),text)

def sidebar_component_snapshot(archive, components):
    """Decode the real sidebar, workspace and launcher CSS from named regions."""
    with tarfile.open(archive) as tar:
        bundle = tar.extractfile('package/lib/client.js').read()
        text = bundle.decode()
        styles, classes = {}, {}
        for component in components:
            region = bundle_region(text, component + '.module.css.mjs')
            literals = re.findall(r'\bconst css(?:\$\d+)? = ("(?:\\.|[^"\\])*");', region)
            if len(literals) != 1:
                raise ValueError('published sidebar CSS literal missing/ambiguous: ' + component)
            styles[component + '.module.css'] = json.loads(literals[0])
            prefix = 'var ' + component + '_module_css_default = '
            if region.count(prefix) != 1:
                raise ValueError('published sidebar class export missing/ambiguous: ' + component)
            mapping, _ = json.JSONDecoder().raw_decode(region.split(prefix, 1)[1])
            if not isinstance(mapping, dict) or not mapping or not all(isinstance(k, str) and isinstance(v, str) for k, v in mapping.items()):
                raise ValueError('published sidebar class export is not a static string map')
            classes[component] = mapping
        return {'css': styles, 'classes': classes, 'bundleSha256': hashlib.sha256(bundle).hexdigest(),
                'manifest': tar.extractfile('package/package.json').read(),
                'license': tar.extractfile('package/LICENSE').read()}

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
            for declaration in package.get('referenceConsumers', []):
                extra = json.loads((source / declaration['path']).read_text())
                if extra[declaration['dependencyField']].get(package['name']) != declaration['dependencySpecifier']:
                    raise ValueError('reference additional consumer drift: ' + declaration['path'])
            for name, sha in package.get('referenceSourceSha256', {}).items():
                if hashlib.sha256((source / name).read_bytes()).hexdigest() != sha:
                    raise ValueError('reference source drift: review the corresponding published package: ' + name)
    return lock

def verify_snapshot(archive, package, folder):
    integrity = 'sha512-' + base64.b64encode(hashlib.sha512(Path(archive).read_bytes()).digest()).decode()
    if integrity != package['integrity']: raise ValueError('published archive integrity mismatch')
    kind = package.get('extractionKind', 'plugin-css')
    if kind == 'sidebar-component-css':
        result = sidebar_component_snapshot(archive, package['styleSheets'])
        if result['bundleSha256'] != package['publishedBundleSha256']:
            raise ValueError('published sidebar bundle hash mismatch')
        for name, css in result['css'].items():
            if (folder / name).read_text() != css:
                raise ValueError('decoded sidebar CSS snapshot mismatch: ' + name)
        for component, mapping in result['classes'].items():
            if json.loads((folder / (component + '-classes.json')).read_text()) != mapping:
                raise ValueError('sidebar class export snapshot mismatch: ' + component)
        for key, name in [('manifest', 'package.json'), ('license', 'LICENSE')]:
            if (folder / name).read_bytes() != result[key]:
                raise ValueError('sidebar package metadata mismatch')
        return
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
                if name == 'modal-layer.json':
                    if json.loads((folder / name).read_text()) != modal_layer_snapshot(archive):
                        raise ValueError('published modal layer snapshot mismatch')
                    continue
                member = 'package/' + ('' if name in ('package.json', 'LICENSE') else 'lib/') + name
                if (folder / name).read_bytes() != tar.extractfile(member).read():
                    raise ValueError('published primitive snapshot mismatch: ' + name)
        return
    extract = {'plugin-css': plugin_style_snapshot, 'market-css': market_style_snapshot,
               'agent-preset-css': agent_preset_style_snapshot,
               'theme-css': theme_style_snapshot, 'terminal-font': terminal_font_snapshot}
    result = extract[kind](archive)
    if result['bundleSha256'] != package['publishedBundleSha256']: raise ValueError('published bundle hash mismatch')
    if kind == 'plugin-css':
        if (folder / 'PluginManagerPage.module.css').read_text() != result['css']: raise ValueError('decoded CSS snapshot mismatch')
        if json.loads((folder / 'classes.json').read_text()) != result['classes']: raise ValueError('class export snapshot mismatch')
    elif kind == 'market-css':
        if (folder / 'DiscoverSection.module.css').read_text() != result['css']: raise ValueError('decoded market CSS snapshot mismatch')
        if json.loads((folder / 'classes.json').read_text()) != result['classes']: raise ValueError('market class export snapshot mismatch')
    elif kind == 'theme-css':
        for name, css in result['css'].items():
            if (folder / name).read_text() != css: raise ValueError('decoded theme CSS snapshot mismatch: ' + name)
        if json.loads((folder / 'styles-order.json').read_text()) != result['order']:
            raise ValueError('published theme injection order snapshot mismatch')
    elif kind == 'agent-preset-css':
        for name, css in result['css'].items():
            if (folder / name).read_text() != css:
                raise ValueError('decoded preset CSS snapshot mismatch: ' + name)
        for component, mapping in result['classes'].items():
            if json.loads((folder / (component + '-classes.json')).read_text()) != mapping:
                raise ValueError('preset class export snapshot mismatch: ' + component)
        if json.loads((folder / 'reader-behavior.json').read_text()) != result['readerBehavior']:
            raise ValueError('published guide behavior snapshot mismatch')
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
