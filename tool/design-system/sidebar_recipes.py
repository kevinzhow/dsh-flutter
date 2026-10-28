"""Compile SidebarRoot, WorkspaceBrowser and signed-out launcher profiles.

The input sheets are decoded from the four pinned published client packages.
A selected state's entire declaration shape is checked before translating it.
Unmigrated animation/drag/search states stay in the audit, not silently styled.
"""
import re

# Declaration shapes intentionally accepted by the migrated static profiles.
# Values are still read from the published CSS; new states/properties fail closed.
TRANSLATED = {
    'SidebarRoot.module.css': ('root topStrip logoRow newSession brandName brandIdentity panelRow panelList regionArea iconButton', [
        ('.root', (), ('--dsh-scrollbar-thumb', '--dsh-scrollbar-thumb-hover', '--dsh-sidebar-inline-padding', 'background', 'box-sizing', 'color', 'display', 'flex-direction', 'font-size', 'height', 'padding')),
        ('[data-platform=darwin] .root', (), ('background',)),
        ('.root.collapsed', (), ('padding',)),
        ('[data-windows-titlebar] .root .logoRow', (), ('height', 'margin', 'padding')),
        ('[data-windows-titlebar] .root.collapsed .logoRow', (), ('height',)),
        ('[data-windows-titlebar] .root:not(.collapsed) .brand', (), ('padding-left',)),
        ('[data-windows-titlebar] .brandIdentity', (), ('transform',)),
        ('[data-windows-titlebar] .brandName', (), ('font-weight',)),
        ('[data-windows-titlebar] .root.collapsed', (), ('padding',)),
        ('[data-windows-titlebar] .root:not(.collapsed) .newSession', (), ('margin-left', 'margin-top')),
        ('[data-windows-titlebar] .collapsed .panelList, [data-windows-titlebar] .collapsed .regionArea, [data-windows-titlebar] .collapsed .footArea', (), ('display',)),
        ('[data-windows-titlebar] .collapsed .newSession', (), ('-webkit-app-region', 'border', 'left', 'margin', 'padding', 'position', 'top', 'z-index')),
        ('[data-windows-titlebar] .railIn .iconButton, [data-windows-titlebar] .railIn .newSession', (), ('animation',)),
        ('[data-windows-titlebar] .collapsed .toggle, [data-windows-titlebar] .collapsed .newSession', (), ('border-radius', 'color', 'height', 'width')),
        ('.root.quietBars', (), ('--dsh-scrollbar-thumb', '--dsh-scrollbar-thumb-hover')),
        ('.railIn .iconButton, .railIn .newSession, .railIn .panelList, .railIn .regionArea', (), ('animation',)),
        ('.topStrip', (), ('align-items', 'box-sizing', 'display', 'flex', 'height', 'justify-content', 'margin', 'padding')),
        ('[data-fullscreen] .topStrip', (), ('justify-content',)),
        ('.topStrip+.logoRow', (), ('margin-top',)),
        ('.logoRow', (), ('align-items', 'box-sizing', 'display', 'flex', 'gap', 'height', 'justify-content', 'margin-bottom', 'overflow', 'padding')),
        ('.collapsed .logoRow', (), ('height', 'justify-content', 'margin-bottom', 'overflow', 'padding')),
        ('.brandIdentity', (), ('align-items', 'display', 'gap', 'height', 'min-width')),
        ('.brandName', (), ('align-items', 'display', 'font-size', 'font-weight', 'gap', 'height', 'letter-spacing', 'line-height', 'min-width')),
        ('.iconButton', (), ('align-items', 'background', 'border', 'border-radius', 'color', 'cursor', 'display', 'flex', 'height', 'justify-content', 'padding', 'position', 'width')),
        ('.iconButton:hover', (), ('background',)),
        ('.iconButton.toggle:focus-visible', (), ('outline', 'outline-offset')),
        ('.collapsed .iconButton', (), ('border-radius', 'height', 'width')),
        ('.collapsed .iconButton', (), ('color',)),
        ('.newSession', (), ('align-items', 'background', 'border', 'border-radius', 'box-sizing', 'color', 'container-type', 'cursor', 'display', 'flex', 'font-size', 'font-weight', 'gap', 'height', 'justify-content', 'line-height', 'margin', 'overflow', 'padding', 'position')),
        ('.newSession:hover', (), ('background',)),
        ('[data-platform=darwin] .newSession', (), ('background',)),
        ('[data-platform=darwin] .newSession:hover', (), ('background',)),
        ('[data-platform=darwin] [data-ds-dark-theme] .newSession', (), ('background',)),
        ('[data-platform=darwin] [data-ds-dark-theme] .newSession:hover', (), ('background',)),
        ('.collapsed .newSession', (), ('align-self', 'background', 'border-color', 'gap', 'height', 'margin', 'padding', 'width')),
        ('.collapsed .newSession:hover', (), ('background',)),
        ('.newSession:is(:hover,:focus-visible) .newSessionLabelMask:has(+.newSessionShortcut)', (), ('mask-image', 'overflow')),
        ('.newSession:is(:hover,:focus-visible) .newSessionShortcut', (), ('opacity',)),
        ('.panelList', (), ('display', 'flex', 'flex-direction', 'gap', 'margin-bottom')),
        ('.panelRow', (), ('align-items', 'background', 'border', 'border-radius', 'box-sizing', 'color', 'cursor', 'display', 'font', 'gap', 'line-height', 'margin', 'min-height', 'padding', 'text-align')),
        ('.panelRow:hover', (), ('background',)),
        ('.panelRow.panelActive', (), ('background', 'color')),
        ('.panelRow:focus-visible', (), ('outline', 'outline-offset')),
        ('.collapsed .panelList', (), ('gap', 'margin-bottom')),
        ('.collapsed .panelRow', (), ('color', 'height', 'justify-content', 'margin', 'padding', 'width')),
        ('.regionArea', (), ('display', 'flex', 'flex-direction', 'margin-left', 'margin-right', 'min-height', 'overflow', 'padding-left')),
        ('.collapsed .regionArea', (), ('margin-left', 'margin-right', 'padding-left')),
        ('.wide, .fading>*, .railIn .iconButton, .railIn .newSession, .railIn .panelList, .railIn .footArea, .railIn .regionArea', ('@media (prefers-reduced-motion: reduce)',), ('animation', 'transition')),
    ]),
    'WorkspaceBrowser.module.css': ('root sectionHeader list fade', [
        ('.root', (), ('--dsh-session-list-edge-inset', '--dsh-session-list-scrollbar-offset', '--dsh-session-list-scrollbar-width', 'box-sizing', 'display', 'flex', 'flex-direction', 'min-height', 'padding-right')),
        ('.root.rail', (), ('padding-right',)),
        ('.sectionHeader', (), ('align-items', 'border-radius', 'box-sizing', 'color', 'display', 'flex', 'gap', 'height', 'justify-content', 'margin-bottom', 'overflow', 'padding-left')),
        ('.root:not(.rail) .sectionHeader', (), ('margin-right', 'margin-top')),
        ('.rail .sectionHeader', (), ('gap', 'justify-content', 'margin-bottom', 'padding-left')),
        ('.fade', (), ('background', 'bottom', 'height', 'left', 'pointer-events', 'position', 'right')),
        ('[data-platform=darwin] .fade', (), ('display',)),
        ('.list', (), ('flex', 'margin-left', 'margin-right', 'min-height', 'overflow-y', 'padding-bottom', 'padding-left', 'padding-right', 'scrollbar-gutter')),
    ]),
    'Rows.module.css': ('projectRow sessionRow title time', [
        ('.projectRow, .sessionRow', (), ('align-items', 'border-radius', 'color', 'cursor', 'display', 'gap', 'padding', 'padding-inline-start', 'user-select')),
        ('.projectRow:hover, .sessionRow:hover, .sessionRow.selected', (), ('background',)),
        ('.projectRow', (), ('align-items', 'box-sizing', 'height')),
        ('.projectRow .rowActions', (), ('height',)),
        ('.sessionRow', (), ('gap', 'height')),
        ('.sessionRow .title', (), ('margin',)),
        ('.projectRow .chevron', (), ('display',)),
        ('.projectRow:hover .chevron', (), ('display',)),
        ('.projectRow:hover .folder', (), ('display',)),
        ('.title', (), ('font-size', 'line-height', 'min-width', 'overflow', 'text-overflow', 'white-space')),
        ('.sessionRow .title', (), ('flex',)),
        ('.sessionRow .title[data-scrolled]', (), ('mask-image',)),
        ('.sessionRow .title[data-clipped]', (), ('mask-image',)),
        ('.sessionRow .title[data-scrolled][data-clipped]', (), ('mask-image',)),
        ('.time', (), ('color', 'flex', 'font-size', 'line-height')),
        ('.sessionRow.archived .title, .searchResultRow.archived .searchResultTitle, .searchResultRow.archived .searchResultWorkspace, .searchResultRow.archived .searchResultSnippet', (), ('color',)),
        ('.projectRow:hover .rowActions, .sessionRow:hover .rowActions, .searchResultRow:hover .rowActions, .projectRow.menuOpen .rowActions, .sessionRow.menuOpen .rowActions', (), ('display',)),
        ('.sessionRow:hover .time, .sessionRow.menuOpen .time, .sessionRow:hover .pinIndicator, .sessionRow.menuOpen .pinIndicator', (), ('display',)),
        ('.sessionRow:hover .title, .sessionRow.menuOpen .title', ('@media (hover: hover)',), ('text-overflow',)),
        ('.projectRow.menuOpen, .sessionRow.menuOpen', (), ('background',)),
        ('.sessionRow.dropBefore, .sessionRow.dropAfter', (), ('position',)),
        ('.sessionRow.dropBefore:before, .sessionRow.dropAfter:after', (), ('background', 'content', 'height', 'left', 'pointer-events', 'position', 'right', 'z-index')),
        ('.sessionRow.dropBefore:before', (), ('top',)),
        ('.sessionRow.dropAfter:after', (), ('bottom',)),
    ]),
    'AccountMenu.module.css': ('trigger signedOutMenu', [
        ('.trigger', (), ('align-items', 'background', 'border', 'border-radius', 'color', 'cursor', 'display', 'font', 'font-size', 'gap', 'height', 'padding', 'user-select', 'width')),
        ('.trigger[data-collapsed=true]', (), ('box-sizing', 'gap', 'height', 'justify-content', 'padding', 'width')),
        ('.trigger:hover', (), ('background',)),
        ('.trigger[data-signed-out=true]:not([data-collapsed=true])', (), ('height', 'line-height', 'padding')),
        ('.signedOutMenu[role=menu]', (), ('max-width', 'min-width', 'padding')),
        ('.signedOutMenu [role=menuitem]', (), ('border-radius', 'font-size', 'gap', 'line-height', 'min-height', 'padding')),
        ('.signedOutMenu [role=menuitem]>span:first-child:not(:last-child)', (), ('color', 'height', 'width')),
        ('.signedOutMenu [role=menuitem]>span:first-child:not(:last-child) svg', (), ('height', 'width')),
    ]),
    'SettingsRoot.module.css': ('triggerRow', [
        ('.triggerRow', (), ('align-items', 'display', 'flex', 'gap', 'margin', 'position', 'width')),
        ('.triggerRow.railRow', (), ('margin', 'width')),
    ]),
}



def build(sheets, *, value, number, token):
    for sheet, (classes, accepted) in TRANSLATED.items():
        pattern = r'\.(?:' + '|'.join(classes.split()) + r')(?![\w-])'
        actual = [(r['selector'], tuple(r['conditions']), tuple(sorted(r['declarations'])))
                  for r in sheets[sheet] if re.search(pattern, r['selector'])]
        if actual != accepted:
            raise ValueError('untranslated sidebar state/property/condition: ' + sheet)
    shell = sheets['SidebarRoot.module.css']
    browser = sheets['WorkspaceBrowser.module.css']
    rows = sheets['Rows.module.css']
    account = sheets['AccountMenu.module.css']
    settings = sheets['SettingsRoot.module.css']

    def state(sheet, selector, names):
        matches = [r for r in sheet if r['selector'] == selector and not r['conditions']]
        if len(matches) != 1 or set(matches[0]['declarations']) != set(names.split()):
            raise ValueError('untranslated sidebar state/property: ' + selector)
        return matches[0]['declarations']

    def n(sheet, selector, prop):
        return number(value(sheet, selector, prop))

    def white_alpha(selector):
        raw = value(shell, selector, 'background')
        if not re.fullmatch(r'#(?:fff|ffffff)[0-9a-f]{1,2}', raw):
            raise ValueError('untranslated sidebar white wash: ' + raw)
        return int(raw[-1] * 2 if len(raw) == 5 else raw[-2:], 16) / 255

    def px(raw, count):
        values = [number(v) if v != '0' else 0.0 for v in raw.split()]
        if len(values) != count:
            raise ValueError('untranslated sidebar box shorthand: ' + raw)
        return values

    root = state(shell, '.root', '--dsh-sidebar-inline-padding height padding box-sizing background color --dsh-scrollbar-thumb --dsh-scrollbar-thumb-hover flex-direction font-size display')
    if root['padding'] != '6px var(--dsh-sidebar-inline-padding)':
        raise ValueError('untranslated sidebar root padding')
    top = state(shell, '.topStrip', 'box-sizing height margin flex justify-content align-items padding display')
    if top['margin'] != '-6px calc(-1 * var(--dsh-sidebar-inline-padding)) 0':
        raise ValueError('untranslated sidebar traffic-light clearance')
    logo = state(shell, '.logoRow', 'box-sizing flex justify-content align-items gap height margin-bottom padding display overflow')
    logo_pad = px(logo['padding'], 4)
    rail = px(value(shell, '.root.collapsed', 'padding'), 3)
    new = state(shell, '.newSession', 'box-sizing border border-radius background height color cursor flex justify-content align-items gap margin padding font-size font-weight line-height display position overflow container-type')
    new_pad = px(new['padding'], 2)
    new_margin = px(new['margin'], 3)
    border = re.fullmatch(r'([\d.]+)px solid var\((--[\w-]+)\)', new['border'])
    if border is None:
        raise ValueError('untranslated sidebar new-session border')
    panel_pad = px(value(shell, '.panelRow', 'padding'), 2)
    top_pad = px(top['padding'], 3)
    brand = state(shell, '.brandName', 'letter-spacing align-items gap min-width height font-size font-weight line-height display')
    letter = re.fullmatch(r'([\d.]+)em', brand['letter-spacing'])
    if letter is None:
        raise ValueError('untranslated sidebar brand tracking')
    more = state(account, '.trigger[data-signed-out=true]:not([data-collapsed=true])', 'height padding line-height')
    more_pad = px(more['padding'], 4)
    frame = state(settings, '.triggerRow', 'flex align-items gap width margin display position')
    if frame['width'] != 'calc(100% + 4px)':
        raise ValueError('untranslated sidebar launcher width')
    frame_margin = px(frame['margin'], 2)
    rail_margin = px(value(settings, '.triggerRow.railRow', 'margin'), 3)
    menu = state(account, '.signedOutMenu[role=menu]', 'min-width max-width padding')
    menurow = state(account, '.signedOutMenu [role=menuitem]', 'min-height gap padding border-radius font-size line-height')
    menupad = px(menurow['padding'], 2)
    icon = state(account, '.signedOutMenu [role=menuitem]>span:first-child:not(:last-child)', 'width height color')
    shared = state(rows, '.projectRow, .sessionRow', 'border-radius user-select align-items gap padding padding-inline-start cursor color display')
    rowpad = px(shared['padding'], 2)
    b_root = state(browser, '.root', '--dsh-session-list-edge-inset --dsh-session-list-scrollbar-width --dsh-session-list-scrollbar-offset min-height box-sizing flex-direction flex padding-right display')
    if b_root['--dsh-session-list-edge-inset'] != 'var(--dsh-sidebar-inline-padding)':
        raise ValueError('untranslated browser edge inset')
    header = state(browser, '.sectionHeader', 'box-sizing border-radius height color flex justify-content align-items gap margin-bottom padding-left display overflow')
    hmargin = state(browser, '.root:not(.rail) .sectionHeader', 'margin-top margin-right')
    group_gap = value(browser, '.groupSection+.groupSection', 'margin-top')
    return {
        'DshSidebarRecipe': {
            'inlinePadding': number(root['--dsh-sidebar-inline-padding']), 'verticalPadding': number(root['padding'].split()[0]),
            'railTopPadding': rail[0], 'railInlinePadding': rail[1], 'railBottomPadding': rail[2],
            'topStripHeight': number(top['height']), 'topStripFootPadding': top_pad[2],
            'logoTopTuck': -n(shell, '.topStrip+.logoRow', 'margin-top'),
            'logoHeight': number(logo['height']), 'logoBottomMargin': number(logo['margin-bottom']),
            'logoTopPadding': logo_pad[0], 'logoLeftPadding': logo_pad[3],
            'railLogoHeight': n(shell, '.collapsed .logoRow', 'height'),
            'railLogoBottomMargin': n(shell, '.collapsed .logoRow', 'margin-bottom'),
            'windowsLogoHeight': n(shell, '[data-windows-titlebar] .root .logoRow', 'height'),
            'brandGap': n(shell, '.brandIdentity', 'gap'), 'brandHeight': n(shell, '.brandIdentity', 'height'),
            'brandFontSize': number(brand['font-size']), 'brandLineHeight': number(brand['line-height']),
            'brandFontWeight': float(brand['font-weight']), 'brandLetterSpacing': float(letter[1])*number(brand['font-size']),
            'iconBox': n(shell, '.iconButton', 'width'), 'railIconBox': n(shell, '.collapsed .iconButton', 'width'),
            'newHeight': number(new['height']), 'newHorizontalPadding': new_pad[1], 'newVerticalPadding': new_pad[0],
            'newInlineMargin': new_margin[1], 'newBottomMargin': new_margin[2],
            'newBorderWidth': float(border[1]), 'newBorderToken': border[2],
            'darwinNewAlpha': white_alpha('[data-platform=darwin] .newSession'),
            'darwinNewHoverAlpha': white_alpha('[data-platform=darwin] .newSession:hover'),
            'darwinNewDarkAlpha': white_alpha('[data-platform=darwin] [data-ds-dark-theme] .newSession'),
            'darwinNewDarkHoverAlpha': white_alpha('[data-platform=darwin] [data-ds-dark-theme] .newSession:hover'),
            'newFillToken': token(new['background']), 'newHoverToken': token(value(shell, '.newSession:hover', 'background')),
            'newGap': n(shell, '.newSessionContent', 'gap'),
            'newFontSize': number(new['font-size']), 'newLineHeight': number(new['line-height']),
            'panelHeight': n(shell, '.panelRow', 'min-height'), 'panelGap': n(shell, '.panelRow', 'gap'),
            'panelHorizontalPadding': panel_pad[1], 'panelVerticalPadding': panel_pad[0],
            'panelListGap': n(shell, '.panelList', 'gap'), 'panelListBottomMargin': n(shell, '.panelList', 'margin-bottom'),
            'railPanelGap': n(shell, '.collapsed .panelList', 'gap'),
            'regionScrollbarExpansion': number(root['--dsh-sidebar-inline-padding']),
            'scrollbarThumbToken': token(root['--dsh-scrollbar-thumb']),
            'scrollbarHoverToken': token(root['--dsh-scrollbar-thumb-hover']),
        },
        'DshWorkspaceBrowserRecipe': {
            'headerHeight': number(header['height']), 'headerLeftPadding': number(header['padding-left']),
            'headerTopMargin': number(hmargin['margin-top']), 'headerRightExpansion': -number(hmargin['margin-right']),
            'headerBottomMargin': number(header['margin-bottom']), 'headerGap': number(header['gap']),
            'iconBox': n(browser, '.iconButton', 'width'),
            'scrollbarWidth': number(b_root['--dsh-session-list-scrollbar-width']),
            'scrollbarOffset': number(b_root['--dsh-session-list-scrollbar-offset']),
            'listBottomPadding': n(browser, '.list', 'padding-bottom'),
            'fadeHeight': n(browser, '.fade', 'height'),
            'groupHeight': n(rows, '.projectRow', 'height'), 'sessionHeight': n(rows, '.sessionRow', 'height'),
            'rowHorizontalPadding': rowpad[1], 'rowGap': number(shared['gap']),
            'groupGap': number(group_gap), 'rowStackGap': n(browser, '.flatList>*+*, .searchTree>[role=treeitem]+[role=treeitem], .groupSection>*+*', 'margin-top'),
            'rowFontSize': n(rows, '.title', 'font-size'), 'rowLineHeight': n(rows, '.title', 'line-height'),
            'timeFontSize': n(rows, '.time', 'font-size'), 'timeLineHeight': n(rows, '.time', 'line-height'),
        },
        'DshSidebarLauncherRecipe': {
            'height': number(more['height']), 'lineHeight': number(more['line-height']),
            'topPadding': more_pad[0], 'rightPadding': more_pad[1], 'bottomPadding': more_pad[2], 'leftPadding': more_pad[3],
            'gap': n(account, '.trigger', 'gap'), 'fontSize': n(account, '.trigger', 'font-size'),
            'railBox': n(account, '.trigger[data-collapsed=true]', 'width'),
            'verticalMargin': frame_margin[0], 'inlineExpansion': -frame_margin[1],
            'railTopMargin': rail_margin[0], 'railBottomMargin': rail_margin[2],
            'menuMinWidth': number(menu['min-width']), 'menuMaxWidth': number(menu['max-width']), 'menuPadding': number(menu['padding']),
            'menuRowHeight': number(menurow['min-height']), 'menuRowGap': number(menurow['gap']),
            'menuRowVerticalPadding': menupad[0], 'menuRowHorizontalPadding': menupad[1],
            'menuIconSize': number(icon['width']), 'menuIconToken': token(icon['color']),
            'menuFontSize': number(menurow['font-size']), 'menuLineHeight': number(menurow['line-height']),
        },
    }
