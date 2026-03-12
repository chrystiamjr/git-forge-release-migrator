import React from 'react';
import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

vi.mock('../../src/components/LocaleSwitcher', () => ({
  default: ({ variant }: { variant: string }) => <div data-testid="locale-switcher">{variant}</div>,
}));

import Root from '../../src/theme/Root';

describe('Root', () => {
  it('renders the floating locale switcher wrapper', () => {
    render(
      <Root>
        <main>content</main>
      </Root>,
    );

    expect(screen.getByText('content')).toBeInTheDocument();
    expect(screen.getByTestId('locale-switcher')).toHaveTextContent('floating');
  });
});
