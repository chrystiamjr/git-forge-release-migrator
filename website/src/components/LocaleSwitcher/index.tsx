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
  let path = pathname;
  if (currentLocale !== defaultLocale) {
    const prefix = `/${currentLocale}`;
    path = pathname.startsWith(prefix) ? pathname.slice(prefix.length) || '/' : pathname;
  }
  if (targetLocale === defaultLocale) {
    return path;
  }
  return `/${targetLocale}${path}`;
}

type Props = {
  /** "inline" — EN|PT pill for the landing page hero (default)
   *  "floating" — single button showing only the alternate locale */
  variant?: 'inline' | 'floating';
};

export default function LocaleSwitcher({ variant = 'inline' }: Props): JSX.Element {
  const {
    i18n: { currentLocale, locales, defaultLocale, localeConfigs },
  } = useDocusaurusContext();
  const { pathname } = useLocation();

  if (variant === 'floating') {
    const target = locales.find((l) => l !== currentLocale);
    if (!target) return <></>;
    const shortLabel = target === 'pt-BR' ? 'PT' : target.toUpperCase();
    const targetLabel = localeConfigs[target]?.label ?? target;
    return (
      <a
        href={buildLocaleUrl(target, defaultLocale, currentLocale, pathname)}
        className={styles.floatingBtn}
        aria-label={`Switch to ${targetLabel}`}
        title={targetLabel}
        hrefLang={localeConfigs[target]?.htmlLang ?? target}
      >
        <span className={styles.floatingIcon}>🌐</span>
        {shortLabel}
      </a>
    );
  }

  return (
    <div className={styles.switcher}>
      {locales.map((locale) => {
        const isActive = locale === currentLocale;
        const shortLabel = locale === 'pt-BR' ? 'PT' : locale.toUpperCase();
        return (
          <a
            key={locale}
            href={buildLocaleUrl(locale, defaultLocale, currentLocale, pathname)}
            className={`${styles.localeBtn} ${isActive ? styles.active : ''}`}
            aria-label={`Switch to ${localeConfigs[locale]?.label ?? locale}`}
            aria-current={isActive ? 'page' : undefined}
            title={localeConfigs[locale]?.label ?? locale}
            hrefLang={localeConfigs[locale]?.htmlLang ?? locale}
          >
            {shortLabel}
          </a>
        );
      })}
    </div>
  );
}
