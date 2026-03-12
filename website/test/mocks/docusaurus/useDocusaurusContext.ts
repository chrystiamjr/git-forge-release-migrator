export default function useDocusaurusContext(): {
  i18n: {
    currentLocale: string;
    locales: string[];
    defaultLocale: string;
    localeConfigs: Record<string, { label?: string; htmlLang?: string }>;
  };
  siteConfig: {
    title: string;
    tagline: string;
  };
} {
  return {
    i18n: {
      currentLocale: 'en',
      locales: ['en', 'pt-BR'],
      defaultLocale: 'en',
      localeConfigs: {
        en: { label: 'English', htmlLang: 'en' },
        'pt-BR': { label: 'Português (Brasil)', htmlLang: 'pt-BR' },
      },
    },
    siteConfig: {
      title: 'GFRM',
      tagline: 'tagline',
    },
  };
}
