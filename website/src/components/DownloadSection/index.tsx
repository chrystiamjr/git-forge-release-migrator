import React, { useEffect, useState } from 'react';
import Translate from '@docusaurus/Translate';
import styles from './index.module.css';

interface ReleaseAsset {
  name: string;
  browser_download_url: string;
  size: number;
}

interface Release {
  tag_name: string;
  html_url: string;
  assets: ReleaseAsset[];
}

type PlatformId = (typeof PLATFORMS)[number]['id'];

const PLATFORMS = [
  {
    id: 'macos-silicon',
    assetName: 'gfrm-macos-silicon.zip',
    label: 'macOS Apple Silicon',
    icon: '🍎',
    hint: 'M1 / M2 / M3',
  },
  {
    id: 'macos-intel',
    assetName: 'gfrm-macos-intel.zip',
    label: 'macOS Intel',
    icon: '🍎',
    hint: 'x86_64',
  },
  {
    id: 'linux',
    assetName: 'gfrm-linux.zip',
    label: 'Linux',
    icon: '🐧',
    hint: 'x86_64',
  },
  {
    id: 'windows',
    assetName: 'gfrm-windows.zip',
    label: 'Windows',
    icon: '🪟',
    hint: 'x86_64',
  },
];

function detectPlatform(): PlatformId | null {
  if (typeof navigator === 'undefined') return 'linux';
  const ua = navigator.userAgent;
  if (ua.includes('Win')) return 'windows';
  // Browsers on Apple Silicon often report an Intel-flavored macOS user agent,
  // so avoid auto-selecting a macOS architecture unless we have a trustworthy signal.
  if (ua.includes('Mac')) return null;
  return 'linux';
}

function formatSize(bytes: number): string {
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

export default function DownloadSection(): JSX.Element {
  const [release, setRelease] = useState<Release | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const detectedPlatform = detectPlatform();

  useEffect(() => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 10_000);
    fetch(
      'https://api.github.com/repos/chrystiamjr/git-forge-release-migrator/releases/latest',
      { signal: controller.signal },
    )
      .then((r) => {
        if (!r.ok) throw new Error(`GitHub API error: ${r.status}`);
        return r.json();
      })
      .then((data: Release) => {
        if (!Array.isArray(data?.assets)) throw new Error('Unexpected API shape');
        setRelease(data);
        setLoading(false);
      })
      .catch(() => {
        setError(true);
        setLoading(false);
      })
      .finally(() => clearTimeout(timer));
    return () => controller.abort();
  }, []);

  const getAsset = (assetName: string) =>
    release?.assets.find((a) => a.name === assetName);

  if (loading) {
    return (
      <div className={styles.skeleton}>
        <div className={styles.skeletonBadge} />
        <div className={styles.skeletonGrid}>
          {[0, 1, 2, 3].map((i) => (
            <div key={i} className={styles.skeletonCard} />
          ))}
        </div>
      </div>
    );
  }

  if (error || !release) {
    return (
      <div className={styles.errorBox}>
        <p>
          <Translate id="downloadSection.error.message">
            Could not load release information.
          </Translate>
        </p>
        <a
          href="https://github.com/chrystiamjr/git-forge-release-migrator/releases"
          target="_blank"
          rel="noopener noreferrer"
          className={styles.fallbackLink}
        >
          <Translate id="downloadSection.error.fallbackLink">
            View all releases on GitHub →
          </Translate>
        </a>
      </div>
    );
  }

  const checksumsAsset = getAsset('checksums-sha256.txt');

  return (
    <div className={styles.wrapper}>
      <div className={styles.header}>
        <span className={styles.versionBadge}>{release.tag_name}</span>
        <a
          href={release.html_url}
          target="_blank"
          rel="noopener noreferrer"
          className={styles.releaseLink}
        >
          <Translate id="downloadSection.releaseNotes">
            Release notes →
          </Translate>
        </a>
      </div>
      <div className={styles.grid}>
        {PLATFORMS.map((platform) => {
          const asset = getAsset(platform.assetName);
          const isDetected = platform.id === detectedPlatform;
          return (
            <div
              key={platform.id}
              className={`${styles.platformCard} ${isDetected ? styles.detected : ''}`}
            >
              {isDetected && (
                <span className={styles.detectedBadge}>
                  <Translate id="downloadSection.detectedBadge">
                    Your platform
                  </Translate>
                </span>
              )}
              <div className={styles.platformIcon}>{platform.icon}</div>
              <div className={styles.platformInfo}>
                <strong>{platform.label}</strong>
                <span className={styles.platformHint}>{platform.hint}</span>
              </div>
              {asset ? (
                <a
                  href={asset.browser_download_url}
                  className={`${styles.downloadBtn} ${isDetected ? styles.downloadBtnPrimary : ''}`}
                >
                  <Translate id="downloadSection.downloadButton">
                    Download
                  </Translate>
                  <span className={styles.fileSize}>{formatSize(asset.size)}</span>
                </a>
              ) : (
                <span className={styles.unavailable}>
                  <Translate id="downloadSection.unavailable">
                    Unavailable
                  </Translate>
                </span>
              )}
            </div>
          );
        })}
      </div>
      {checksumsAsset && (
        <div className={styles.checksumRow}>
          <a
            href={checksumsAsset.browser_download_url}
            className={styles.checksumLink}
          >
            ↓ checksums-sha256.txt
          </a>
          <span className={styles.checksumHint}>
            <Translate id="downloadSection.checksumHint">
              Verify your download with SHA256
            </Translate>
          </span>
        </div>
      )}
    </div>
  );
}
