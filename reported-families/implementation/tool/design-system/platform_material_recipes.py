"""Keep published platform menu colours scoped instead of globalizing them."""
import re


def build(rules):
    selectors = {
        'html[data-platform=darwin] body': 'darwinLightMenuFill',
        'html[data-platform=darwin] body[data-ds-dark-theme]': 'darwinDarkMenuFill',
    }
    fields = {}
    for rule in rules:
        selector = rule['selector']
        if (rule['conditions'] or selector not in selectors
                or set(rule['declarations']) != {'--dsw-specific-menu'}
                or selectors[selector] in fields):
            raise ValueError('untranslated platform menu material scope: ' + selector)
        fill = rule['declarations']['--dsw-specific-menu']
        if not re.fullmatch(r'#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{5})?', fill):
            raise ValueError('unsupported published platform menu colour: ' + fill)
        fields[selectors[selector]] = fill
    if set(fields) != set(selectors.values()):
        raise ValueError('missing published platform menu material scope')
    return {'DshPlatformMaterialRecipe': fields}
