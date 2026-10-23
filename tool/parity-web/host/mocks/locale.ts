// A translator over dsh's REAL dictionaries, with the lookup and `{param}` interpolation of dsh's locale
// service (ui locale: packages/client/locale/src/client/index.ts, `LocaleRuntime.translate`). That class
// needs a cordis Context, so it is not importable; the rule it implements is small and is reproduced here:
//
//   chain    = the active locale, then its fallback (zh falls back to en), then en
//   template = first hit of the namespace dictionary over the chain, else the shared `common` dictionary over
//              the chain, else the key itself
//   params   = `template.replace(/\{(\w+)\}/g, ...)`, an unknown name stays as written
import { en as commonEn, zh as commonZh } from '@dsh/locale/src/locales/index.ts'

export type Dictionary = Readonly<Record<string, string>>
export type Translate = (key: string, params?: Record<string, unknown>) => string

const COMMON = { en: commonEn as Dictionary, zh: commonZh as Dictionary }

/** Built-in locale id of a manifest locale (`en`, `zh-CN`): dsh ships `zh` and `en`. */
function builtInLocale(locale: string): 'zh' | 'en' {
  return locale.toLowerCase().startsWith('zh') ? 'zh' : 'en'
}

/**
 * Bind a namespace's dictionary pair to a locale.
 * @param locale - manifest locale, `en` or `zh-CN`.
 * @param dictionaries - the namespace's real `en` and `zh` dictionaries.
 */
export function createTranslator(locale: string, dictionaries: { en: Dictionary; zh: Dictionary }): Translate {
  const active = builtInLocale(locale)
  const chain: ('zh' | 'en')[] = active === 'zh' ? ['zh', 'en'] : ['en']
  const lookup = (set: { en: Dictionary; zh: Dictionary }, key: string) => {
    for (const id of chain) {
      const value = set[id][key]
      if (value !== undefined) return value
    }
    return undefined
  }
  return (key, params) => {
    const template = lookup(dictionaries, key) ?? lookup(COMMON, key) ?? key
    if (!params) return template
    return template.replace(/\{(\w+)\}/g, (match, name: string) => (name in params ? String(params[name]) : match))
  }
}
