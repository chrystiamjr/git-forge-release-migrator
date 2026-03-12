export function buildLocaleUrl(
  targetLocale: string,
  defaultLocale: string,
  currentLocale: string,
  pathname: string,
): string {
  let resolvedPath = pathname;

  if (currentLocale !== defaultLocale) {
    const localePrefix = `/${currentLocale}`;
    resolvedPath = pathname.startsWith(localePrefix) ? pathname.slice(localePrefix.length) || '/' : pathname;
  }

  if (targetLocale === defaultLocale) {
    return resolvedPath;
  }

  return `/${targetLocale}${resolvedPath === '/' ? '' : resolvedPath}`;
}
