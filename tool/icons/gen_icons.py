#!/usr/bin/env python3
"""Generate packages/dsh_ui/lib/src/dsh_icons.g.dart from dsh's own icon artwork.

dsh draws its product icons as inline SVG (packages/client/ui-primitives/src/icons). The Flutter client draws the same
geometry: this script reads the artwork of the icons named in ICONS from the pinned dsh checkout and writes their path
data, so a changed icon upstream is one regeneration away.

    gen_icons.py [--check]

The pinned checkout is found through $DSH_SRC or <repo>/.local/dsh-src.
"""
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'packages' / 'dsh_ui' / 'lib' / 'src' / 'dsh_icons.g.dart'
SRC = pathlib.Path(os.environ.get('DSH_SRC', str(ROOT / '.local' / 'dsh-src')))
ICON_DIR = SRC / 'packages' / 'client' / 'ui-primitives' / 'src' / 'icons'

# Exported dsh icon name -> Dart identifier. Add a row when a feature needs another glyph.
ICONS = {
    'IconApiOutlineRegular': 'api',
    'IconEditOutlineRegular': 'edit',
    'IconBrowseOutlineRegular': 'browse',
    'IconSearchOutlineRegular': 'search',
    'IconGlobeOutlineRegular': 'globe',
    'IconChecklistOutlineRegular': 'checklist',
    'IconQuestionOutlineRegular': 'question',
    'IconSparkleRegular': 'sparkle',
    'IconCodeOutlineRegular': 'code',
    'IconChevronDownOutlineRegular': 'chevronDown',
    'IconChevronUpOutlineRegular': 'chevronUp',
    'IconChevronRightOutlineRegular': 'chevronRight',
    'IconInspectOutlineRegular': 'inspect',
    'IconCopyOutlineRegular': 'copy',
    'IconCheckOutlineRegular': 'check',
    'IconWrapFillRegular': 'wrap',
    'IconNowrapFillRegular': 'nowrap',
    'IconPlayOutlineRegular': 'play',
    'IconUsersOutlineRegular': 'users',
    'IconClockOutlineRegular': 'clock',
    'IconGoalOutlineRegular': 'goal',
    'IconPlanOutlineRegular': 'plan',
    'IconBranchOutlineRegular': 'branch',
    'IconAgentPresetOutlineRegular': 'agentPreset',
    'IconCordisPluginOutlineRegular': 'cordisPlugin',
    'IconPlusOutlineMedium': 'plus',
    'IconCloseOutlineRegular': 'close',
    'IconCloseFillRegular': 'closeFill',
    'IconRefreshOutlineRegular': 'refresh',
    'IconLoadingOutlineRegular': 'loading',
    'IconDownloadOutlineRegular': 'download',
    'IconShareOutlineRegular': 'share',
    'IconFolderCloseRegular': 'folderClose',
    'IconFolderOpenRegular': 'folderOpen',
    'IconSettingsOutlineMedium': 'settingsMedium',
    'IconPersonalizationOutlineMedium': 'personalizationMedium',
    'IconLightOutlineMedium': 'lightMedium',
    'IconDarkOutlineMedium': 'darkMedium',
    'IconFollowsystemOutlineMedium': 'followSystemMedium',
    'IconDataOutlineRegular': 'data',
    'IconWarningOutlineRegular': 'warning',
    'IconPaperPlaneOutlineRegular': 'paperPlane',
    'IconPaperclipOutlineRegular': 'paperclip',
    'IconCompactOutlineRegular': 'compact',
    'IconProjectAddOutlineRegular': 'projectAdd',
}
# Permission glyphs: ui-primitives PermissionIcon.tsx draws them as local `function XArtwork({ size = 16, ..., strokeWidth })`
# components; the Regular variants (1px stroke) are the ones the composer and the settings rows use.
# Shared artwork drawn directly, without an `Icon*` export of its own: the session reference glyph
# (ReferenceIcon.tsx draws ChatLinesOutlineArtwork at the regular 1px stroke).
SHARED_ARTWORK = {
    'ChatLinesOutlineArtwork': ('ReferenceIconRegular(session)', 'chatLines'),
}
PERMISSION_ICONS = {
    'ReadOnlyArtwork': ('PermissionIconReadOnlyRegular', 'permissionReadOnly'),
    'WorkspaceWriteArtwork': ('PermissionIconWorkspaceWriteRegular', 'permissionWorkspaceWrite'),
    'FullAccessArtwork': ('PermissionIconFullAccessRegular', 'permissionFullAccess'),
    'AutoReviewArtwork': ('PermissionIconAutoReviewRegular', 'permissionAutoReview'),
}
STROKE = {'ICON_REGULAR_STROKE': 1.0, 'ICON_MEDIUM_STROKE': 1.3}


def read(name):
    return (ICON_DIR / name).read_text()


def artworks(text):
    """name -> (default size, svg body) for every `const XArtwork = (...) => ( <svg ...> )`."""
    out = {}
    for m in re.finditer(r'const (\w+Artwork) = \(\{([^}]*)\}[^=]*=>\s*\(\s*(<svg[\s\S]*?</svg>)\s*\)', text):
        size = re.search(r'size = (\d+)', m.group(2))
        out[m.group(1)] = (int(size.group(1)) if size else 16, m.group(3))
    # `const XArtwork = (props) => (<YArtwork {...props} size={props.size ?? 14} />)`: an alias of another artwork.
    for m in re.finditer(r'const (\w+Artwork) = \(props: \w+\) => \(\s*<(\w+Artwork)\b([^>]*)/>', text):
        if m.group(2) in out and m.group(1) not in out:
            size = re.search(r'size=\{props\.size \?\? (\d+)\}', m.group(3))
            out[m.group(1)] = (int(size.group(1)) if size else out[m.group(2)][0], out[m.group(2)][1])
    return out


def circle_path(cx, cy, r):
    return 'M%g %gm-%g 0a%g %g 0 1 0 %g 0a%g %g 0 1 0 -%g 0' % (cx, cy, r, r, r, 2 * r, r, r, 2 * r)


def elements(svg):
    out = []
    for m in re.finditer(r'<(path|circle|rect|line)\b([^>]*?)/>', svg):
        tag, attrs = m.group(1), dict(re.findall(r'(\w+)="([^"]*)"', m.group(2)))
        if tag == 'path':
            d = attrs['d']
        elif tag == 'circle':
            d = circle_path(float(attrs['cx']), float(attrs['cy']), float(attrs['r']))
        elif tag == 'line':
            d = 'M%s %sL%s %s' % (attrs['x1'], attrs['y1'], attrs['x2'], attrs['y2'])
        else:
            x, y, w, h = (float(attrs.get(k, 0)) for k in ('x', 'y', 'width', 'height'))
            d = 'M%g %gh%gv%gh-%gz' % (x, y, w, h, w)
        fill = attrs.get('fill') == 'currentColor'
        cap = 'square' if 'strokeLinecap="square"' in m.group(2) else ('round' if 'strokeLinecap="round"' in m.group(2) else 'butt')
        evenodd = attrs.get('fillRule') == 'evenodd' or 'fillRule="evenodd"' in m.group(2)
        opacity = float(attrs['opacity']) if 'opacity' in attrs else 1.0
        out.append((d, fill, cap, evenodd, opacity))
    return out


def build():
    index = read('index.tsx')
    arts = artworks(index)
    arts.update(artworks(read('shared-artwork.tsx')))
    rows = []
    for export, ident in ICONS.items():
        m = re.search(r'export const %s = \(props: IconProps\) =>\s*\(?\s*<(\w+)\b([^>]*)/>' % export, index)
        if m is None:
            sys.exit('gen_icons: %s not found in index.tsx' % export)
        art, extra = m.group(1), m.group(2)
        if art not in arts:
            sys.exit('gen_icons: artwork %s of %s not found' % (art, export))
        size, svg = arts[art]
        size_override = re.search(r'size=\{props\.size \?\? (\d+)\}', extra)
        if size_override:
            size = int(size_override.group(1))
        vb = re.search(r'viewBox="0 0 (\d+) (\d+)"', svg)
        stroke = re.search(r'strokeWidth=\{(\w+)\}', extra)
        width = STROKE[stroke.group(1)] if stroke else 1.0
        els = elements(svg)
        if not els:
            sys.exit('gen_icons: no geometry in %s' % export)
        rows.append((ident, export, int(vb.group(1)), size, width, els))
    for art, (export, ident) in SHARED_ARTWORK.items():
        if art not in arts:
            sys.exit('gen_icons: shared artwork %s not found' % art)
        size, svg = arts[art]
        vb = re.search(r'viewBox="0 0 (\d+) (\d+)"', svg)
        els = elements(svg)
        if not els:
            sys.exit('gen_icons: no geometry in %s' % art)
        rows.append((ident, export, int(vb.group(1)), size, STROKE['ICON_REGULAR_STROKE'], els))
    permission = read('../PermissionIcon.tsx')
    for artwork, (export, ident) in PERMISSION_ICONS.items():
        m = re.search(r'function %s\(\{ size = (\d+)[^)]*\)[^{]*\{\s*return \(\s*(<svg[\s\S]*?</svg>)\s*\)' % artwork, permission)
        if m is None:
            sys.exit('gen_icons: %s not found in PermissionIcon.tsx' % artwork)
        vb = re.search(r'viewBox="0 0 (\d+) (\d+)"', m.group(2))
        els = elements(m.group(2))
        if not els:
            sys.exit('gen_icons: no geometry in %s' % artwork)
        rows.append((ident, export, int(vb.group(1)), int(m.group(1)), STROKE['ICON_REGULAR_STROKE'], els))
    lines = [
        '// GENERATED by tool/icons/gen_icons.py from dsh ui-primitives icons. Do not edit.',
        '// ignore_for_file: lines_longer_than_80_chars',
        '',
        "import 'dsh_icon_data.dart';",
        '',
        '/// dsh product icons, drawn from the same SVG path data as the web client.',
        'abstract final class DshIcons {',
    ]
    for ident, export, view, size, width, els in rows:
        lines.append('  /// `%s`.' % export)
        lines.append('  static const %s = DshIconData(' % ident)
        lines.append('    viewBox: %d,' % view)
        lines.append('    size: %d,' % size)
        lines.append('    strokeWidth: %s,' % width)
        lines.append('    shapes: [')
        for d, fill, cap, evenodd, opacity in els:
            lines.append("      DshIconShape('%s', fill: %s, cap: DshIconCap.%s, evenOdd: %s%s)," % (
                d, str(fill).lower(), cap, str(evenodd).lower(), '' if opacity == 1.0 else ', opacity: %s' % opacity))
        lines.append('    ],')
        lines.append('  );')
    lines.append('}')
    return '\n'.join(lines) + '\n'


def formatted(text):
    """The text as `dart format` writes it (the generated file is checked by the format guard too)."""
    import subprocess
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / 'gen.dart'
        path.write_text(text)
        subprocess.run(['dart', 'format', str(path)], check=True, capture_output=True)
        return path.read_text()


def main():
    if not ICON_DIR.exists():
        print('gen_icons: tool unavailable: no dsh checkout at %s' % SRC, file=sys.stderr)
        sys.exit(2)
    text = formatted(build())
    if '--check' in sys.argv:
        if not OUT.exists() or OUT.read_text() != text:
            print('gen_icons: %s is stale; run tool/icons/gen_icons.py' % OUT.relative_to(ROOT), file=sys.stderr)
            sys.exit(1)
        print('gen_icons: up to date')
        return
    OUT.write_text(text)
    print('gen_icons: wrote %s (%d icons)' % (OUT.relative_to(ROOT), len(ICONS) + len(SHARED_ARTWORK) + len(PERMISSION_ICONS)))


main()
