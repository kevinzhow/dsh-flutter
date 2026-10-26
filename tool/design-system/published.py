"""Read published bundle CSS without executing JavaScript."""
from pathlib import Path
import argparse,base64,hashlib,json,re,tarfile

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

def verify_snapshot(archive, package, folder):
    integrity = 'sha512-' + base64.b64encode(hashlib.sha512(Path(archive).read_bytes()).digest()).decode()
    if integrity != package['integrity']: raise ValueError('published archive integrity mismatch')
    result = plugin_style_snapshot(archive)
    if result['bundleSha256'] != package['publishedBundleSha256']: raise ValueError('published bundle hash mismatch')
    if (folder / 'PluginManagerPage.module.css').read_text() != result['css']: raise ValueError('decoded CSS snapshot mismatch')
    if json.loads((folder / 'classes.json').read_text()) != result['classes']: raise ValueError('class export snapshot mismatch')
    for key, name in [('manifest', 'package.json'), ('license', 'LICENSE')]:
        if (folder / name).read_bytes() != result[key]: raise ValueError('package metadata snapshot mismatch')

def main():
    parser = argparse.ArgumentParser(description='Verify reproducible CSS extraction from the locked published plugin archive (no JS execution).')
    parser.add_argument('--archive', type=Path, required=True)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    package = json.loads((here / 'sources.lock.json').read_text())['packages'][1]
    verify_snapshot(args.archive, package, here / 'upstream' / package['snapshotFolder'])
    print('design-system: published archive integrity and decoded CSS/class snapshots agree')

if __name__ == '__main__': main()
