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
  // Avoid trailing slash on locale root (e.g. /pt-BR not /pt-BR/)
  return `/${targetLocale}${path === '/' ? '' : path}`;
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

  // Hard navigation is required for locale switches: the SPA router for the
  // current locale has no knowledge of the other locale's routes, so
  // history.push() would silently 404. window.location.assign() forces a full
  // page reload, which is what Docusaurus's built-in localeDropdown does too.
  function switchTo(targetLocale: string): void {
    window.location.assign(buildLocaleUrl(targetLocale, defaultLocale, currentLocale, pathname));
  }

  if (variant === 'floating') {
    const target = locales.find((l) => l !== currentLocale);
    if (!target) return <></>;
    const shortLabel = target === 'pt-BR' ? 'PT' : target.toUpperCase();
    const targetLabel = localeConfigs[target]?.label ?? target;
    return (
      <button
        type="button"
        className={styles.floatingBtn}
        onClick={() => switchTo(target)}
        aria-label={`Switch to ${targetLabel}`}
        title={targetLabel}
        lang={localeConfigs[target]?.htmlLang ?? target}
      >
        <span className={styles.floatingIcon}>🌐</span>
        {shortLabel}
      </button>
    );
  }

  return (
    <div className={styles.switcher}>
      {locales.map((locale) => {
        const isActive = locale === currentLocale;
        const shortLabel = locale === 'pt-BR' ? 'PT' : locale.toUpperCase();
        return (
          <button
            type="button"
            key={locale}
            className={`${styles.localeBtn} ${isActive ? styles.active : ''}`}
            onClick={() => { if (!isActive) switchTo(locale); }}
            aria-label={`Switch to ${localeConfigs[locale]?.label ?? locale}`}
            aria-current={isActive ? 'page' : undefined}
            title={localeConfigs[locale]?.label ?? locale}
            disabled={isActive}
            lang={localeConfigs[locale]?.htmlLang ?? locale}
          >
            {shortLabel}
          </button>
        );
      })}
    </div>
  );
}
