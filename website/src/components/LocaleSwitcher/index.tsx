import React from 'react';
import { useLocation } from '@docusaurus/router';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import { buildLocaleUrl } from './buildLocaleUrl';
import styles from './index.module.css';

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

  function switchTo(targetLocale: string): void {
    window.location.assign(buildLocaleUrl(targetLocale, defaultLocale, currentLocale, pathname));
  }

  if (variant === 'floating') {
    const target = locales.find((locale) => locale !== currentLocale);

    if (!target) {
      return <></>;
    }

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
            onClick={() => {
              if (!isActive) {
                switchTo(locale);
              }
            }}
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
