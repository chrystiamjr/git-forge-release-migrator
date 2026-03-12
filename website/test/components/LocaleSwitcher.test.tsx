import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const assignMock = vi.fn();

vi.mock('@docusaurus/useDocusaurusContext', () => ({
  default: () => ({
    i18n: {
      currentLocale: 'en',
      locales: ['en', 'pt-BR'],
      defaultLocale: 'en',
      localeConfigs: {
        en: { label: 'English', htmlLang: 'en' },
        'pt-BR': { label: 'Português (Brasil)', htmlLang: 'pt-BR' },
      },
    },
  }),
}));

vi.mock('@docusaurus/router', () => ({
  useLocation: () => ({ pathname: '/intro' }),
}));

import LocaleSwitcher from '../../src/components/LocaleSwitcher';

describe('LocaleSwitcher', () => {
  let originalLocationDescriptor: PropertyDescriptor | undefined;

  beforeEach(() => {
    assignMock.mockReset();
    originalLocationDescriptor = Object.getOwnPropertyDescriptor(window, 'location');
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: {
        ...window.location,
        assign: assignMock,
      },
    });
  });

  afterEach(() => {
    if (originalLocationDescriptor) {
      Object.defineProperty(window, 'location', originalLocationDescriptor);
    } else {
      delete (window as Window & { location?: Location }).location;
    }
  });

  it('renders floating button and navigates to alternate locale', () => {
    render(<LocaleSwitcher variant="floating" />);

    const button = screen.getByRole('button', { name: 'Switch to Português (Brasil)' });
    fireEvent.click(button);

    expect(assignMock).toHaveBeenCalledWith('/pt-BR/intro');
  });

  it('renders inline switch with active locale disabled', () => {
    render(<LocaleSwitcher variant="inline" />);

    expect(screen.getByRole('button', { name: 'Switch to English' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Switch to Português (Brasil)' })).toBeEnabled();
  });
});
