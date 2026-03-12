import type { Release } from '../domain/release';
import { LATEST_RELEASE_API_URL, REQUEST_TIMEOUT_MS } from './constants';

export async function fetchLatestRelease(): Promise<Release> {
  const controller = new AbortController();
  const timeoutTimer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(LATEST_RELEASE_API_URL, { signal: controller.signal });

    if (!response.ok) {
      throw new Error(`GitHub API error: ${response.status}`);
    }

    const release = (await response.json()) as Release;

    if (!Array.isArray(release?.assets)) {
      throw new Error('Unexpected API shape');
    }

    return release;
  } finally {
    clearTimeout(timeoutTimer);
    controller.abort();
  }
}
