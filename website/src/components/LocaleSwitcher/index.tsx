import React from 'react';
import { useHistory, useLocation } from '@docusaurus/router';
import { translate } from '@docusaurus/Translate';
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
  const history = useHistory();
  const { pathname } = useLocation();

  if (variant === 'floating') {
    const target = locales.find((l) => l !== currentLocale);
    if (!target) return <></>;
    const shortLabel = target === 'pt-BR' ? 'PT' : target.toUpperCase();
    const targetLabel = localeConfigs[target]?.label ?? target;
    return (
      <button
        type="button"
        className={styles.floatingBtn}
        onClick={() =>
          history.push(buildLocaleUrl(target, defaultLocale, currentLocale, pathname))
        }
        aria-label={translate(
          {
            id: 'localeSwitcher.switchTo',
            message: 'Switch to {targetLabel}',
          },
          { targetLabel },
        )}
        title={targetLabel}
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
                history.push(buildLocaleUrl(locale, defaultLocale, currentLocale, pathname));
              }
            }}
            aria-label={translate(
              {
                id: 'localeSwitcher.switchTo',
                message: 'Switch to {targetLabel}',
              },
              { targetLabel: localeConfigs[locale]?.label ?? locale },
            )}
            aria-current={isActive ? 'page' : undefined}
            title={localeConfigs[locale]?.label ?? locale}
            disabled={isActive}
          >
            {shortLabel}
          </button>
        );
      })}
    </div>
  );
}
