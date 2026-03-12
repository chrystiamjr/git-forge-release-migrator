import { describe, expect, it } from 'vitest';
import { buildLocaleUrl } from '../../src/components/LocaleSwitcher/buildLocaleUrl';

describe('buildLocaleUrl', () => {
  it('returns default locale path without prefix', () => {
    expect(buildLocaleUrl('en', 'en', 'pt-BR', '/pt-BR/intro')).toBe('/intro');
  });

  it('returns locale root without trailing slash', () => {
    expect(buildLocaleUrl('pt-BR', 'en', 'en', '/')).toBe('/pt-BR');
  });

  it('keeps nested path for non-default locale target', () => {
    expect(buildLocaleUrl('pt-BR', 'en', 'en', '/commands/migrate')).toBe('/pt-BR/commands/migrate');
  });
});
