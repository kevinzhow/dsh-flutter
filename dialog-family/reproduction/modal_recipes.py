"""Compile the published Modal shell and its agent-guide reader profile."""
import re


MODAL = {
    '.root': 'pointer-events position inset z-index display align-items justify-content padding',
    '.mask': 'position inset backdrop-filter',
    '.mask::after': 'content position inset background animation',
    '.dialog': 'box-sizing position z-index display flex-direction gap width padding overflow border border-radius background box-shadow animation',
    '.dialog:focus': 'outline',
    '.content': 'display flex-direction width',
    '.header': 'display align-items justify-content gap padding',
    '.title': 'margin font-size line-height font-weight color',
    '.close': 'flex display align-items justify-content width height border border-radius background cursor color',
    '.close:hover': 'background',
    '.description': 'margin padding font-size line-height font-weight color',
    '.body': 'display flex-direction min-width margin-top padding',
    '.footer': 'display align-items justify-content gap padding',
}

GUIDE = {
    '.guideDialog': 'box-sizing width height max-height padding gap',
    '.guideLayout': 'display flex-direction min-height height',
    '.guideHeader': 'flex padding',
    '.guideTitleRow': 'display align-items justify-content gap',
    '.guideTitle': 'margin font-size line-height font-weight',
    '.guideIntro': 'margin font-size line-height color',
    '.guideClose': 'width height min-height padding border-radius color',
    '.guideTabs': 'flex margin',
    '.guidePanel': '--dsh-scrollbar-thumb --dsh-scrollbar-thumb-hover flex min-height overflow-y overscroll-behavior scrollbar-gutter padding font-size color overflow-wrap',
    '.guidePanel:focus-visible': 'outline outline-offset',
    '.guidePanel h3': 'margin font-size line-height font-weight',
    '.guidePanel h3:first-child': 'margin-top',
    '.guidePanel p': 'margin font-size line-height color',
    '.guidePanel blockquote': 'margin padding border border-radius background',
    '.guidePanel blockquote p': 'margin color',
    '.guidePanel[data-guide-page=usage] p': 'margin-bottom font-size line-height color',
    '.guidePanel[data-guide-page=usage] h3': 'margin',
    '.guideExample+.guideExample': 'margin-top',
    '.guideExampleHeader': 'display flex-wrap align-items gap margin-bottom',
    '.guideExampleTag': 'flex-shrink gap',
    '.guidePanel[data-guide-page=usage] blockquote': 'margin padding',
    '.guidePanel[data-guide-page=usage] blockquote p': 'margin font-size line-height color',
}


def normalize(rule):
    def compact(text):
        text = re.sub(r"\[data-guide-page=['\"]usage['\"]\]", '[data-guide-page=usage]', text)
        text = re.sub(r'(?<![\w.])0\.(\d+)', r'.\1', text)
        return re.sub(r'\s*([,+>])\s*', r'\1', text.strip())
    return {'selector': compact(rule['selector']), 'conditions': rule['conditions'],
            'declarations': {k: compact(v) for k, v in rule['declarations'].items()}}


def verify_guide_source(published, original):
    if [normalize(r) for r in published] != [normalize(r) for r in original]:
        raise ValueError('reference guide CSS differs from pinned published preset package')


def resolve_context(context, *, number, value):
    tokens = context['themeTokens']
    expected = {(':root', ()): {'--ds-transition-duration', '--ds-ease-in-out'},
                ('body', ()): {'--dsw-mask-blur'}}
    seen = set()
    for rule in tokens:
        key = (rule['selector'], tuple(rule['conditions']))
        if key in seen or key not in expected or set(rule['declarations']) != expected[key]:
            raise ValueError('untranslated modal theme token scope')
        seen.add(key)
    if seen != set(expected): raise ValueError('missing modal theme tokens')
    timing = next(r['declarations'] for r in tokens if r['selector'] == ':root')
    mask = next(r['declarations'] for r in tokens if r['selector'] == 'body')
    rules = context['scrollbarRules']
    schema = {
        'body': '--dsh-scrollbar-thumb --dsh-scrollbar-thumb-hover --dsh-scrollbar-thumb-border --dsh-scrollbar-track-margin --dsh-scrollbar-width',
        '::-webkit-scrollbar': 'width height',
        '::-webkit-scrollbar-track': 'margin-block background',
        '::-webkit-scrollbar-thumb': 'border corner-shape background background-clip border-radius',
        '::-webkit-scrollbar-thumb:hover': 'background-color',
        '::-webkit-scrollbar-corner': 'background',
    }
    seen = set()
    fallback = ('body, body *', ('@supports not selector(::-webkit-scrollbar)',))
    for rule in rules:
        key = (rule['selector'], tuple(rule['conditions']))
        if key in seen: raise ValueError('duplicate modal scrollbar rule')
        seen.add(key)
        if key == fallback:
            if rule['declarations'] != {'scrollbar-width': 'thin', 'scrollbar-color': 'var(--dsh-scrollbar-thumb) transparent'}:
                raise ValueError('untranslated modal scrollbar fallback')
        elif (rule['conditions'] or rule['selector'] not in schema
              or set(rule['declarations']) != set(schema[rule['selector']].split())):
            raise ValueError('untranslated modal scrollbar state/property')
    if seen != {(name, ()) for name in schema} | {fallback}:
        raise ValueError('missing modal scrollbar state')
    fixed = {
        'body': {'--dsh-scrollbar-thumb': 'var(--dsw-alias-scrollbar-bg-l1)',
                 '--dsh-scrollbar-thumb-hover': 'var(--dsw-alias-scrollbar-hover-l1)'},
        '::-webkit-scrollbar': {'width': 'var(--dsh-scrollbar-width)', 'height': 'var(--dsh-scrollbar-width)'},
        '::-webkit-scrollbar-track': {'margin-block': 'var(--dsh-scrollbar-track-margin)', 'background': '0 0'},
        '::-webkit-scrollbar-thumb': {'border': 'var(--dsh-scrollbar-thumb-border) solid transparent',
                                    'corner-shape': 'round', 'background': 'var(--dsh-scrollbar-thumb)',
                                    'background-clip': 'content-box'},
        '::-webkit-scrollbar-thumb:hover': {'background-color': 'var(--dsh-scrollbar-thumb-hover)'},
        '::-webkit-scrollbar-corner': {'background': '0 0'},
    }
    for selector, declarations in fixed.items():
        for prop, expected_value in declarations.items():
            if value(rules, selector, prop) != expected_value:
                raise ValueError('untranslated modal scrollbar structure: ' + selector + '/' + prop)
    return {'duration': timing['--ds-transition-duration'], 'ease': timing['--ds-ease-in-out'],
            'maskBlur': mask['--dsw-mask-blur'], 'modalBehavior': context['modalBehavior'],
            'readerBehavior': context['readerBehavior'],
            'scrollbar': {'scrollbarWidth': number(value(rules, 'body', '--dsh-scrollbar-width')),
                          'scrollbarRadius': number(value(rules, '::-webkit-scrollbar-thumb', 'border-radius')),
                          'scrollbarThumbBorderWidth': number(value(rules, 'body', '--dsh-scrollbar-thumb-border')),
                          'scrollbarTrackMargin': number(value(rules, 'body', '--dsh-scrollbar-track-margin'))}}


def build(modal, guide, context, *, value, number, token, font_token):
    context = resolve_context(context, number=number, value=value)
    def validate(rules, schema, family):
        seen = set()
        for rule in rules:
            selector, props, conditions = rule['selector'], rule['declarations'], rule['conditions']
            key = (selector, tuple(conditions))
            if key in seen:
                raise ValueError('duplicate ' + family + ' state: ' + selector)
            seen.add(key)
            if family == 'modal' and conditions:
                if conditions == ['@keyframes modalEnter'] and selector in ('from', 'to'):
                    if props != {'opacity': '0' if selector == 'from' else '1'}:
                        raise ValueError('untranslated modal opacity animation')
                elif (conditions != ['@media (prefers-reduced-motion: reduce)']
                      or selector != '.mask::after, .dialog' or props != {'animation': 'none'}):
                    raise ValueError('untranslated modal conditional state: ' + selector)
                continue
            if conditions or selector not in schema or set(props) != set(schema[selector].split()):
                raise ValueError('untranslated ' + family + ' state/property: ' + selector)
        required = {(name, ()) for name in schema}
        if family == 'modal':
            required |= {('from', ('@keyframes modalEnter',)), ('to', ('@keyframes modalEnter',)),
                         ('.mask::after, .dialog', ('@media (prefers-reduced-motion: reduce)',))}
        if seen != required:
            raise ValueError('missing ' + family + ' state')

    validate(modal, MODAL, 'modal')
    validate(guide, GUIDE, 'guide')

    def get(rules, selector, prop): return value(rules, selector, prop)
    def px(rules, selector, prop):
        raw = get(rules, selector, prop)
        return 0.0 if raw == '0' else number(raw)
    def tok(rules, selector, prop): return token(get(rules, selector, prop))
    def fixed(rules, selector, declarations, family):
        for prop, expected in declarations.items():
            if get(rules, selector, prop) != expected:
                raise ValueError('untranslated ' + family + ' structure: ' + selector + '/' + prop)
    def zero_or_px(raw): return 0.0 if raw == '0' else number(raw)
    def edges(raw):
        parts = list(map(zero_or_px, raw.split()))
        if len(parts) == 1: return parts * 4
        if len(parts) == 2: return [parts[0], parts[1], parts[0], parts[1]]
        if len(parts) == 3: return [parts[0], parts[1], parts[2], parts[1]]
        if len(parts) == 4: return parts
        raise ValueError('unsupported modal/guide edge expression: ' + raw)
    def min_size(raw):
        match = re.fullmatch(r'min\(([^,]+),\s*100%\)', raw)
        if match is None: raise ValueError('unsupported modal/guide bounded size: ' + raw)
        return number(match[1])
    def weight(raw):
        if not re.fullmatch(r'[1-9]00', raw): raise ValueError('unsupported modal/guide font weight')
        return float(raw)
    def uniform_side_padding(rules, selector):
        t, r, b, l = edges(get(rules, selector, 'padding'))
        if t or b or l != r: raise ValueError('unsupported modal horizontal content padding')
        return l

    for selector, declarations in {
        '.root': {'pointer-events': 'auto', 'position': 'fixed', 'inset': '0', 'z-index': '1000',
                  'display': 'flex', 'align-items': 'center', 'justify-content': 'center'},
        '.mask': {'position': 'absolute', 'inset': 'var(--dsh-frame-chrome-top, 0px) 0 0',
                  'backdrop-filter': 'var(--dsw-mask-blur)'},
        '.mask::after': {'content': "''", 'position': 'absolute', 'inset': '0',
                        'animation': 'modalEnter var(--ds-transition-duration) var(--ds-ease-in-out)'},
        '.dialog': {'box-sizing': 'border-box', 'position': 'relative', 'z-index': '1', 'display': 'flex',
                    'flex-direction': 'column', 'overflow': 'hidden', 'border': '0',
                    'animation': 'modalEnter var(--ds-transition-duration) var(--ds-ease-in-out)'},
        '.dialog:focus': {'outline': 'none'},
        '.content': {'display': 'flex', 'flex-direction': 'column', 'width': '100%'},
        '.header': {'display': 'flex', 'align-items': 'center', 'justify-content': 'space-between'},
        '.title': {'margin': '0'},
        '.close': {'flex': 'none', 'display': 'inline-flex', 'align-items': 'center', 'justify-content': 'center',
                   'border': 'none', 'background': 'transparent', 'cursor': 'pointer'},
        '.description': {'margin': '0'},
        '.body': {'display': 'flex', 'flex-direction': 'column', 'min-width': '0'},
        '.footer': {'display': 'flex', 'align-items': 'center', 'justify-content': 'flex-end'},
    }.items(): fixed(modal, selector, declarations, 'modal')
    for selector, declarations in {
        '.guideDialog': {'box-sizing': 'border-box', 'max-height': '100%', 'padding': '0', 'gap': '0'},
        '.guideLayout': {'display': 'flex', 'flex-direction': 'column', 'min-height': '0', 'height': '100%'},
        '.guideHeader': {'flex': 'none'},
        '.guideTitleRow': {'display': 'flex', 'align-items': 'center', 'justify-content': 'space-between'},
        '.guideTitle': {'margin': '0'},
        '.guideTabs': {'flex': 'none'},
        '.guidePanel': {'flex': '1', 'min-height': '0', 'overflow-y': 'auto', 'overscroll-behavior': 'contain',
                        'scrollbar-gutter': 'stable', 'overflow-wrap': 'anywhere'},
        '.guidePanel blockquote': {'border': '0'},
        '.guidePanel blockquote p': {'margin': '0'},
        '.guidePanel[data-guide-page=usage] h3': {'margin': '0'},
        '.guideExampleHeader': {'display': 'flex', 'flex-wrap': 'wrap', 'align-items': 'center'},
        '.guideExampleTag': {'flex-shrink': '0'},
        '.guidePanel[data-guide-page=usage] blockquote p': {'margin': '0'},
    }.items(): fixed(guide, selector, declarations, 'guide')

    root = re.fullmatch(r'max\(([^,]+),\s*var\(--dsh-frame-overlay-top,\s*([^\)]+)\)\)\s+(.+)', get(modal, '.root', 'padding'))
    if root is None or number(root[1]) != number(root[2]):
        raise ValueError('unsupported modal overlay padding expression')
    dialog_padding = edges(get(modal, '.dialog', 'padding'))
    if any(dialog_padding[i] for i in (0, 1, 3)):
        raise ValueError('unsupported modal card padding')
    header = edges(get(modal, '.header', 'padding'))
    close_size = px(modal, '.close', 'width')
    if close_size != px(modal, '.close', 'height'):
        raise ValueError('unsupported nonsquare modal close')
    duration = re.fullmatch(r'([\d.]+)(ms|s)', context['duration'])
    curve = re.fullmatch(r'cubic-bezier\(\s*([\d.-]+),\s*([\d.-]+),\s*([\d.-]+),\s*([\d.-]+)\s*\)', context['ease'])
    if duration is None or curve is None or context['maskBlur'] != 'none':
        raise ValueError('unsupported modal duration, easing, or mask blur')
    modal_icon = re.findall(r'IconCloseOutlineRegular,\s*\{\s*size:\s*([\d.]+)\s*\}', context['modalBehavior']['modal'])
    guide_icon = re.findall(r'IconCloseOutlineRegular,\s*\{\s*size:\s*([\d.]+)\s*\}', context['readerBehavior']['region'])
    example_icon = re.findall(r'IconListPenOutlineRegular,\s*\{\s*size:\s*([\d.]+)\s*\}', context['readerBehavior']['region'])
    if len(modal_icon) != 1 or len(guide_icon) != 1 or len(example_icon) != 1:
        raise ValueError('published modal/guide close or example icon declaration changed')
    modal_recipe = {
        'rootMargin': number(root[1]), 'rootHorizontalMargin': number(root[3]),
        'maskChromeTopFallback': 0.0, 'defaultWidth': min_size(get(modal, '.dialog', 'width')),
        'gap': px(modal, '.dialog', 'gap'), 'paddingBottom': dialog_padding[2],
        **dict(zip(('headerTop', 'headerRight', 'headerBottom', 'headerLeft'), header)),
        'headerGap': px(modal, '.header', 'gap'),
        'titleFontSize': px(modal, '.title', 'font-size'), 'titleLineHeight': px(modal, '.title', 'line-height'),
        'titleFontToken': font_token(px(modal, '.title', 'font-size'), px(modal, '.title', 'line-height')),
        'titleWeight': weight(get(modal, '.title', 'font-weight')), 'titleLabelToken': tok(modal, '.title', 'color'),
        'closeSize': close_size, 'closeIconSize': float(modal_icon[0]),
        'closeRadiusToken': tok(modal, '.close', 'border-radius'), 'closeLabelToken': tok(modal, '.close', 'color'),
        'closeHoverToken': tok(modal, '.close:hover', 'background'),
        'descriptionHorizontalPadding': uniform_side_padding(modal, '.description'),
        'descriptionFontSize': px(modal, '.description', 'font-size'),
        'descriptionLineHeight': px(modal, '.description', 'line-height'),
        'descriptionWeight': weight(get(modal, '.description', 'font-weight')),
        'descriptionLabelToken': tok(modal, '.description', 'color'),
        'bodyMarginTop': px(modal, '.body', 'margin-top'), 'bodyHorizontalPadding': uniform_side_padding(modal, '.body'),
        'footerGap': px(modal, '.footer', 'gap'), 'footerHorizontalPadding': uniform_side_padding(modal, '.footer'),
        'maskToken': tok(modal, '.mask::after', 'background'), 'backgroundToken': tok(modal, '.dialog', 'background'),
        'radiusToken': tok(modal, '.dialog', 'border-radius'), 'elevationToken': tok(modal, '.dialog', 'box-shadow'),
        'animationDurationToken': '--ds-transition-duration', 'easeToken': '--ds-ease-in-out',
        'animationMs': float(duration[1]) * (1000 if duration[2] == 's' else 1),
        **{name: float(curve[i]) for i, name in enumerate(('curveX1', 'curveY1', 'curveX2', 'curveY2'), 1)},
        'maskBlurToken': '--dsw-mask-blur', 'maskBlur': context['maskBlur'],
    }

    header = edges(get(guide, '.guideHeader', 'padding'))
    intro = edges(get(guide, '.guideIntro', 'margin'))
    tabs = edges(get(guide, '.guideTabs', 'margin'))
    if any(intro[i] for i in (1, 2, 3)) or tabs[1] != tabs[3]:
        raise ValueError('unsupported guide intro or tab margins')
    close_size = px(guide, '.guideClose', 'width')
    if close_size != px(guide, '.guideClose', 'height') or close_size != px(guide, '.guideClose', 'min-height'):
        raise ValueError('unsupported guide close dimensions')
    outline = re.fullmatch(r'var\((--[\w-]+)\) solid var\((--[\w-]+),\s*var\((--[\w-]+)\)\)', get(guide, '.guidePanel:focus-visible', 'outline'))
    if outline is None: raise ValueError('unsupported guide panel focus outline')
    panel = edges(get(guide, '.guidePanel', 'padding'))
    heading = edges(get(guide, '.guidePanel h3', 'margin'))
    paragraph = edges(get(guide, '.guidePanel p', 'margin'))
    quote_margin = edges(get(guide, '.guidePanel blockquote', 'margin'))
    quote_padding = edges(get(guide, '.guidePanel blockquote', 'padding'))
    usage_quote_margin = edges(get(guide, '.guidePanel[data-guide-page=usage] blockquote', 'margin'))
    usage_quote_padding = edges(get(guide, '.guidePanel[data-guide-page=usage] blockquote', 'padding'))
    if (heading[1] or heading[3] or any(paragraph[i] for i in (0, 1, 3))
            or quote_margin[1] or quote_margin[3] or quote_padding[0] != quote_padding[2] or quote_padding[1] != quote_padding[3]
            or usage_quote_margin[0] != usage_quote_margin[2] or usage_quote_margin[1] or usage_quote_margin[3]
            or usage_quote_padding[0] != usage_quote_padding[2] or usage_quote_padding[1] != usage_quote_padding[3]):
        raise ValueError('unsupported guide prose edge structure')
    example_gap = get(guide, '.guideExampleHeader', 'gap').split()
    if len(example_gap) != 2: raise ValueError('unsupported guide example header gap')
    paragraph_size = px(guide, '.guidePanel p', 'font-size')
    guide_recipe = {
        'width': min_size(get(guide, '.guideDialog', 'width')), 'height': min_size(get(guide, '.guideDialog', 'height')),
        **dict(zip(('headerTop', 'headerRight', 'headerBottom', 'headerLeft'), header)),
        'titleGap': px(guide, '.guideTitleRow', 'gap'), 'titleFontSize': px(guide, '.guideTitle', 'font-size'),
        'titleLineHeight': px(guide, '.guideTitle', 'line-height'), 'titleWeight': weight(get(guide, '.guideTitle', 'font-weight')),
        'titleFontToken': font_token(px(guide, '.guideTitle', 'font-size'), px(guide, '.guideTitle', 'line-height')),
        'introGap': intro[0], 'introFontSize': px(guide, '.guideIntro', 'font-size'),
        'introLineHeight': px(guide, '.guideIntro', 'line-height'), 'introLabelToken': tok(guide, '.guideIntro', 'color'),
        'introFontToken': font_token(px(guide, '.guideIntro', 'font-size'), px(guide, '.guideIntro', 'line-height')),
        'closeSize': close_size, 'closeIconSize': float(guide_icon[0]),
        'closePadding': px(guide, '.guideClose', 'padding'),
        'closeRadiusToken': tok(guide, '.guideClose', 'border-radius'), 'closeLabelToken': tok(guide, '.guideClose', 'color'),
        'tabsTopMargin': tabs[0], 'tabsHorizontalMargin': tabs[1], 'tabsBottomMargin': tabs[2],
        **dict(zip(('panelTop', 'panelRight', 'panelBottom', 'panelLeft'), panel)),
        'panelFontSize': px(guide, '.guidePanel', 'font-size'), 'panelLabelToken': tok(guide, '.guidePanel', 'color'),
        'panelFontToken': font_token(px(guide, '.guidePanel', 'font-size'), modal_recipe['titleLineHeight']),
        'panelFocusWidthToken': outline[1], 'panelFocusToken': outline[2], 'panelFocusFallbackToken': outline[3],
        'panelFocusOffset': px(guide, '.guidePanel:focus-visible', 'outline-offset'),
        'scrollbarThumbToken': tok(guide, '.guidePanel', '--dsh-scrollbar-thumb'),
        'scrollbarHoverToken': tok(guide, '.guidePanel', '--dsh-scrollbar-thumb-hover'),
        **context['scrollbar'],
        'headingTop': heading[0], 'headingBottom': heading[2],
        'headingFirstTop': px(guide, '.guidePanel h3:first-child', 'margin-top'),
        'headingFontSize': px(guide, '.guidePanel h3', 'font-size'),
        'headingLineHeight': px(guide, '.guidePanel h3', 'line-height'),
        'headingWeight': weight(get(guide, '.guidePanel h3', 'font-weight')),
        'paragraphBottom': paragraph[2], 'paragraphFontSize': paragraph_size,
        'paragraphLineHeight': paragraph_size * number(get(guide, '.guidePanel p', 'line-height'), ''),
        'paragraphLabelToken': tok(guide, '.guidePanel p', 'color'),
        'quoteTop': quote_margin[0], 'quoteBottom': quote_margin[2],
        'quoteVerticalPadding': quote_padding[0], 'quoteHorizontalPadding': quote_padding[1],
        'quoteRadiusToken': tok(guide, '.guidePanel blockquote', 'border-radius'),
        'quoteBackgroundToken': tok(guide, '.guidePanel blockquote', 'background'),
        'quoteLabelToken': tok(guide, '.guidePanel blockquote p', 'color'),
        'usageParagraphBottom': px(guide, '.guidePanel[data-guide-page=usage] p', 'margin-bottom'),
        'usageParagraphFontSize': px(guide, '.guidePanel[data-guide-page=usage] p', 'font-size'),
        'usageParagraphLineHeight': px(guide, '.guidePanel[data-guide-page=usage] p', 'line-height'),
        'usageParagraphLabelToken': tok(guide, '.guidePanel[data-guide-page=usage] p', 'color'),
        'exampleGap': px(guide, '.guideExample+.guideExample', 'margin-top'),
        'exampleHeaderRowGap': number(example_gap[0]), 'exampleHeaderColumnGap': number(example_gap[1]),
        'exampleHeaderBottom': px(guide, '.guideExampleHeader', 'margin-bottom'),
        'exampleTagGap': px(guide, '.guideExampleTag', 'gap'),
        'exampleIconSize': float(example_icon[0]),
        'usageQuoteVerticalMargin': usage_quote_margin[0], 'usageQuoteVerticalPadding': usage_quote_padding[0],
        'usageQuoteHorizontalPadding': usage_quote_padding[1],
        'usageQuoteFontSize': px(guide, '.guidePanel[data-guide-page=usage] blockquote p', 'font-size'),
        'usageQuoteLineHeight': px(guide, '.guidePanel[data-guide-page=usage] blockquote p', 'line-height'),
        'usageQuoteLabelToken': tok(guide, '.guidePanel[data-guide-page=usage] blockquote p', 'color'),
    }
    return {'DshModalRecipe': modal_recipe, 'DshGuideReaderRecipe': guide_recipe}
