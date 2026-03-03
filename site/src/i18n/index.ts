import { translations as en } from './translations/en';
import { translations as ja } from './translations/ja';
import { glossary as enGlossary } from './glossary/en';
import { glossary as jaGlossary } from './glossary/ja';
import type { GlossaryEntry } from './glossary/en';

export type Lang = 'en' | 'ja';

const allTranslations: Record<Lang, Record<string, string>> = { en, ja };
const allGlossaries: Record<Lang, Record<string, GlossaryEntry>> = { en: enGlossary, ja: jaGlossary };

export function t(lang: Lang, key: string, vars?: Record<string, string>): string {
  let str = allTranslations[lang]?.[key] ?? allTranslations.en[key] ?? key;
  if (vars) {
    for (const [k, v] of Object.entries(vars)) {
      str = str.replace(`{${k}}`, v);
    }
  }
  return str;
}

export function getGlossary(lang: Lang): Record<string, GlossaryEntry> {
  return allGlossaries[lang] ?? allGlossaries.en;
}

export function getLocalizedPath(lang: Lang, base: string): string {
  const b = base.endsWith('/') ? base : base + '/';
  return lang === 'ja' ? `${b}ja/` : b;
}

export function getAlternateLang(lang: Lang): Lang {
  return lang === 'en' ? 'ja' : 'en';
}

export type { GlossaryEntry };
