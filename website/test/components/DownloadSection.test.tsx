import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import DownloadSection from '../../src/components/DownloadSection';

const originalFetch = global.fetch;
const originalUserAgent = window.navigator.userAgent;

function mockUserAgent(userAgent: string): void {
  Object.defineProperty(window.navigator, 'userAgent', {
    value: userAgent,
    configurable: true,
  });
}

describe('DownloadSection', () => {
  beforeEach(() => {
    mockUserAgent('Mozilla/5.0 (X11; Linux x86_64)');
  });

  afterEach(() => {
    global.fetch = originalFetch;
    mockUserAgent(originalUserAgent);
    vi.restoreAllMocks();
  });

  it('renders error state when release fetch fails', async () => {
    global.fetch = vi.fn().mockRejectedValue(new Error('network')) as unknown as typeof fetch;

    render(<DownloadSection />);

    await waitFor(() => {
      expect(screen.getByText('Could not load release information.')).toBeInTheDocument();
    });
  });

  it('renders release cards and detected platform after successful fetch', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        tag_name: 'v1.0.0',
        html_url: 'https://example.com/release/v1.0.0',
        assets: [
          {
            name: 'gfrm-linux.zip',
            browser_download_url: 'https://example.com/gfrm-linux.zip',
            size: 8_388_608,
          },
          {
            name: 'checksums-sha256.txt',
            browser_download_url: 'https://example.com/checksums-sha256.txt',
            size: 512,
          },
        ],
      }),
    }) as unknown as typeof fetch;

    render(<DownloadSection />);

    await waitFor(() => {
      expect(screen.getByText('v1.0.0')).toBeInTheDocument();
    });

    expect(screen.getByText('Your platform')).toBeInTheDocument();
    expect(screen.getAllByText('Download').length).toBeGreaterThan(0);
    expect(screen.getByText('↓ checksums-sha256.txt')).toBeInTheDocument();
  });
});
