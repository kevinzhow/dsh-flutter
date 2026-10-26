"""Compile the consumed menu family fields from published stylesheets.

The full source schema remains an explicit gate, including pending submenu,
footer and sticky-group rules. New states/properties fail before code emission.
"""
from pathlib import Path
import json,re
HERE = Path(__file__).resolve().parent

def portal_margin(placement, gap, contract):
    margin = re.search(r'const MARGIN = ([\d.]+);', placement)
    if margin is None: raise ValueError('unsupported menu portal margin')
    expected = contract.replace('$margin', margin[1]).replace('$gap', format(gap, 'g'))
    if re.sub(r'\s+', ' ', placement).strip() != expected:
        raise ValueError('untranslated menu portal placement')
    return float(margin[1])


def build(sheets, *, value, number, token, css_rules):
    consumed = set()
    original_value = value
    def tracked(rules, selector, prop):
        consumed.add((id(rules), selector, prop))
        return original_value(rules, selector, prop)
    value = tracked
    full_contract = json.loads((HERE / 'menu-contract.json').read_text())
    contract = full_contract['rules']
    for name, schema in contract.items():
        current = sheets[name]
        if name == 'dockkit.module.css':
            current = [r for r in current if re.search(r'\.(?:menu|menuItem)(?![\w-])', r['selector'])]
        if name == 'PluginManagerPage.module.css':
            current = [r for r in current if '.addMenu' in r['selector']]
        if len(current) != len(schema) or any(r['conditions'] for r in current) or {r['selector'] for r in current} != set(schema):
            raise ValueError('untranslated menu state/condition: ' + name)
        for rule in current:
            if set(rule['declarations']) != set(schema[rule['selector']]):
                raise ValueError('untranslated menu property: ' + name + ' ' + rule['selector'])
    menu, surface, plugin = (sheets[n] for n in ['Menu.module.css', 'MenuSurface.module.css', 'PluginManagerPage.module.css'])
    get = lambda selector, prop: value(menu, selector, prop)
    px = lambda selector, prop: number(get(selector, prop))
    tok = lambda selector, prop: token(get(selector, prop))
    typography = json.loads((HERE.parents[1] / 'packages/dsh_theme/assets/themes/official.theme.json').read_text())['common']['typography']
    def font_token(size, line=None):
        choices = [name for name, style in typography.items() if style['size'] == size and
                   style['family'] == 'text' and style['weight'] == 400 and style['style'] == 'normal']
        if line is not None:
            choices = [name for name in choices if typography[name]['line'] == line]
        if len(choices) != 1: raise ValueError('ambiguous menu typography rung for size ' + str(size))
        return choices[0]
    def pair(raw):
        words = raw.split()
        if len(words) != 2: raise ValueError('unsupported menu padding/margin: ' + raw)
        return [number(w) for w in words]
    normal_pad = pair(get('.item','padding')); compact_pad = pair(get('.compactList .item','padding'))
    heading_pad = pair(get('.label','padding')); compact_heading = pair(get('.compactList .label','padding'))
    separator = pair(get('.separator','margin'))
    theme = css_rules((HERE / 'upstream/ui-theme/gradient-shadow-text.css').read_text())
    filter_css = value(theme, 'body', '--dsw-menu-backdrop-filter')
    match = re.fullmatch(r'blur\(([\d.]+)px\) saturate\(([\d.]+)%\)', filter_css)
    if match is None: raise ValueError('unsupported menu backdrop filter')
    height = px('.item','min-height'); font = px('.item','font-size'); line = px('.item','line-height')
    for selectors, edge in [(['.itemIcon', '.itemIcon svg, .check'], px('.itemIcon','width')),
                            (['.compactList .itemIcon', '.compactList .itemIcon svg, .compactList .check'], px('.compactList .itemIcon','width'))]:
        if any(px(selector, prop) != edge for selector in selectors for prop in ['width', 'height']):
            raise ValueError('untranslated nonsquare menu icon/check')
    # Preserve unsupported structural values until the renderer is changed.
    fixed = {
      '.item': {'display':'flex','align-items':'center','width':'100%','border':'none','background':'transparent','cursor':'pointer','text-align':'left'},
      '.item:focus-visible:not(:disabled)': {'outline':'none'}, '.item:disabled': {'cursor':'not-allowed'},
      '.selected': {'background':'transparent'}, '.danger:focus-visible:not(:disabled)': {'outline':'none'},
      '.shortcut': {'flex':'none', 'margin-inline-start':'auto'},
    }
    for selector, fields in fixed.items():
        for prop, expected in fields.items():
            if get(selector,prop) != expected: raise ValueError('untranslated menu structural value: ' + selector + '/' + prop)
    footer_border = re.fullmatch(r'([\d.]+)px solid var\((--[\w-]+)\)', get('.footer', 'border-top'))
    if footer_border is None: raise ValueError('unsupported menu footer border')
    viewport = re.fullmatch(r'calc\(100vh - ([\d.]+)px - max\(([\d.]+)px, var\(--dsh-frame-overlay-top, ([\d.]+)px\)\)\)', get('.scrollable', 'max-height'))
    if viewport is None: raise ValueError('unsupported menu viewport height')
    anchor_gap = re.fullmatch(r'calc\(100% \+ ([\d.]+)px\)', get('.list', 'top'))
    if anchor_gap is None: raise ValueError('unsupported menu anchor gap')
    portal = json.loads((HERE / 'upstream/ui-primitives/menu-portal.json').read_text())
    metrics = {
      'DshMenuRecipe': {
        'padding': px('.list, .submenu','padding'), 'minWidth':px('.list','min-width'), 'maxWidth':px('.list','max-width'),
        'anchorGap':float(anchor_gap[1]), 'viewportBottomMargin':float(viewport[1]),
        'viewportTopMargin':float(viewport[2]), 'frameOverlayTopFallback':float(viewport[3]),
        'portalMargin':portal_margin(portal['placement'], float(anchor_gap[1]), full_contract['portalPlacement']),
        'compactMinWidth': px('.list.compactList, .submenu.compactList','min-width'),
        'compactPadding':px('.list.compactList, .submenu.compactList','padding'),
        'height':height,'denseHeight':px('.denseList .item','min-height'),'compactHeight':px('.compactList .item','min-height'),
        'verticalPadding':normal_pad[0],'horizontalPadding':normal_pad[1],
        'denseVerticalPadding':px('.denseList .item','padding-block'),
        'compactVerticalPadding':compact_pad[0],'compactHorizontalPadding':compact_pad[1],
        'fontSize':font,'lineHeight':line,'fontToken':font_token(font),
        'compactFontSize':px('.compactList .item','font-size'),'compactLineHeight':px('.compactList .item','line-height'),'compactFontToken':font_token(px('.compactList .item','font-size')),
        'gap':px('.item','gap'),'compactGap':px('.compactList .item','gap'),
        'iconSize':px('.itemIcon','width'),'compactIconSize':px('.compactList .itemIcon','width'),
        'radiusToken':tok('.item','border-radius'),'compactRadiusToken':tok('.compactList .item','border-radius'),
        'labelToken':tok('.item','color'),'iconToken':tok('.itemIcon','color'),
        'shortcutFontSize':px('.shortcut .shortcutKeys','font-size'),
        'shortcutLineHeight':px('.shortcut .shortcutKeys','line-height'),
        'shortcutFontToken':font_token(px('.shortcut .shortcutKeys','font-size')),
        'shortcutColorToken':tok('.shortcut .shortcutKeys','color'),
        'checkToken':tok('.check','color'),'selectedFillToken':tok('.selectedFill','background'),
        'hoverToken':tok('.item:hover:not(:disabled)','background'),'focusToken':tok('.item:focus-visible:not(:disabled)','background'),
        'dangerToken':tok('.danger','color'),'dangerHoverToken':tok('.danger:hover:not(:disabled)','background'),
        'dangerIconToken':tok('.danger .itemIcon','color'),'dangerFocusToken':tok('.danger:focus-visible:not(:disabled)','background'),
        'disabledOpacity':number(get('.item:disabled','opacity'),''),
        'headingVerticalPadding':heading_pad[0],'headingHorizontalPadding':heading_pad[1],
        'denseHeadingVerticalPadding':px('.denseList .label','padding-block'),
        'compactHeadingVerticalPadding':compact_heading[0],'compactHeadingHorizontalPadding':compact_heading[1],
        'headingFontSize':px('.label','font-size'),'headingLineHeight':px('.label','line-height'),
        'compactHeadingFontSize':px('.compactList .label','font-size'),'compactHeadingLineHeight':px('.compactList .label','line-height'),
        'headingFontToken':font_token(px('.label','font-size')),'compactHeadingFontToken':font_token(px('.compactList .item','font-size')),
        'headingToken':tok('.label','color'), 'separatorWidth':px('.separator','height'),
        'separatorVerticalMargin':separator[0],'separatorHorizontalMargin':separator[1],
        'compactSeparatorMargin':px('.compactList .separator','margin'),'separatorToken':tok('.separator','background'),
      },
      'DshMenuFooterRecipe': {
        'marginTop':px('.footer','margin-top'), 'paddingTop':px('.footer','padding-top'),
        'borderWidth':float(footer_border[1]), 'borderToken':footer_border[2],
      },
      'DshMenuSurfaceRecipe': {
        'radiusToken':token(value(surface,'.surface, .backing','border-radius')),
        'compactRadiusToken':token(value(surface,'.compact','border-radius')),
        'fillToken':token(value(surface,'.material','background')),
        'shadowToken':tok('.list, .submenu','box-shadow'),
        'strokeToken':tok('.list, .submenu','--dsw-elevation-stroke-color'),
        'darkStrokeToken':token(value(theme,'body[data-ds-dark-theme] [data-menu-material]','--dsw-elevation-stroke-color')),
        'blurSigma':float(match[1]),'saturation':float(match[2])/100,
      },
    }
    width_limit = value(plugin, '.addMenu', 'max-width')
    limit = re.fullmatch(r'calc\(100vw - ([\d.]+)px\)', width_limit)
    if limit is None: raise ValueError('unsupported plugin menu viewport width')
    add = '.addMenu [role=menuitem]'; pad = pair(value(plugin,add,'padding'))
    metrics['DshPluginAddMenuRecipe'] = {
      'width':number(value(plugin,'.addMenu','width')), 'viewportMargin':float(limit[1])/2,
      'height':number(value(plugin,add,'height')), 'verticalPadding':pad[0],'horizontalPadding':pad[1],
      'gap':number(value(plugin,add,'gap')),'descriptionGap':number(value(plugin,'.addMenuItem','gap')),
      'descriptionFontSize':number(value(plugin,'.addMenuDescription','font-size')),
      'descriptionFontToken':font_token(number(value(plugin,'.addMenuDescription','font-size')), number(value(plugin,'.addMenuDescription','line-height'))),
      'descriptionLineHeight':number(value(plugin,'.addMenuDescription','line-height')),
      'descriptionMaxHeight':number(value(plugin,'.addMenuDescription','max-height')),
      'descriptionToken':token(value(plugin,'.addMenuDescription','color')),
    }
    dock = sheets['dockkit.module.css']
    dp = lambda selector, prop: value(dock, selector, prop)
    pad = pair(dp('.menuItem', 'padding'))
    border = re.fullmatch(r'([\d.]+)px solid var\((--[\w-]+)\)', dp('.menu', 'border'))
    size = re.fullmatch(r'calc\(var\(--dsh-content-font-size-secondary, ([\d.]+)px\) - ([\d.]+)px\)', dp('.menuItem', 'font-size'))
    if border is None or size is None: raise ValueError('unsupported dock menu border/font expression')
    metrics['DshDockMenuRecipe'] = {
      'minWidth':number(dp('.menu','min-width')), 'padding':number(dp('.menu','padding')),
      'borderWidth':float(border[1]), 'borderToken':border[2],
      'verticalPadding':pad[0], 'horizontalPadding':pad[1],
      'fontBase':float(size[1])-float(size[2]), 'fontScale':'secondary',
      'radiusToken':token(dp('.menuItem','border-radius')),
      'labelToken':token(dp('.menuItem','color')), 'hoverToken':token(dp('.menuItem:hover','background')),
    }
    # Every value not consumed by a generated field must stay at its explicitly
    # audited value. This includes pending structures; they cannot drift silently.
    for name, schema in contract.items():
        for selector, props in schema.items():
            for prop, expected in props.items():
                if (id(sheets[name]), selector, prop) not in consumed and original_value(sheets[name], selector, prop) != expected:
                    raise ValueError('untranslated menu structural value: ' + name + ' ' + selector + '/' + prop)
    return metrics
