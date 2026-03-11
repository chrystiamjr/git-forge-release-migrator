import React from 'react';
import { useLocation } from '@docusaurus/router';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import styles from './index.module.css';

function buildLocaleUrl(
  targetLocale: string,
  defaultLocale: string,
  currentLocale: string,
  pathname: string,
): string {
  // Strip current locale prefix from path (non-default locales are prefixed)
  let path = pathname;
  if (currentLocale !== defaultLocale) {
    path = pathname.replace(new RegExp(`^/${currentLocale}`), '') || '/';
  }
  // Prefix target locale (unless it's the default)
  if (targetLocale === defaultLocale) {
    return path;
  }
  return `/${targetLocale}${path}`;
}

export default function LocaleSwitcher(): JSX.Element {
  const {
    i18n: { currentLocale, locales, defaultLocale, localeConfigs },
  } = useDocusaurusContext();
  const { pathname } = useLocation();

  return (
    <div className={styles.switcher}>
      {locales.map((locale) => {
        const isActive = locale === currentLocale;
        const label = localeConfigs[locale]?.htmlLang ?? locale;
        const shortLabel = locale === 'pt-BR' ? 'PT' : locale.toUpperCase();
        return (
          <a
            key={locale}
            href={buildLocaleUrl(locale, defaultLocale, currentLocale, pathname)}
            className={`${styles.localeBtn} ${isActive ? styles.active : ''}`}
            aria-label={`Switch to ${localeConfigs[locale]?.label ?? locale}`}
            aria-current={isActive ? 'true' : undefined}
            title={localeConfigs[locale]?.label ?? locale}
            hrefLang={label}
          >
            {shortLabel}
          </a>
        );
      })}
    </div>
  );
}
