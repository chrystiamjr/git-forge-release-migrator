import React, { useEffect, useState } from 'react';
import Translate from '@docusaurus/Translate';
import { detectPlatform } from './application/detectPlatform';
import { fetchLatestRelease } from './application/fetchLatestRelease';
import { PLATFORMS, type PlatformId } from './domain/platform';
import type { Release, ReleaseAsset } from './domain/release';
import styles from './index.module.css';
import ChecksumsLink from './presentation/ChecksumsLink';
import DownloadError from './presentation/DownloadError';
import DownloadSkeleton from './presentation/DownloadSkeleton';
import PlatformCard from './presentation/PlatformCard';

const CHECKSUMS_ASSET_NAME = 'checksums-sha256.txt';

function findAssetByName(release: Release, assetName: string): ReleaseAsset | undefined {
  return release.assets.find((asset) => asset.name === assetName);
}

export default function DownloadSection(): JSX.Element {
  const [release, setRelease] = useState<Release | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<boolean>(false);
  const [detectedPlatform, setDetectedPlatform] = useState<PlatformId | null>(null);

  useEffect(() => {
    setDetectedPlatform(detectPlatform(navigator.userAgent));
  }, []);

  useEffect(() => {
    let mounted = true;

    async function loadRelease(): Promise<void> {
      try {
        const fetchedRelease = await fetchLatestRelease();

        if (mounted) {
          setRelease(fetchedRelease);
          setLoading(false);
        }
      } catch {
        if (mounted) {
          setError(true);
          setLoading(false);
        }
      }
    }

    void loadRelease();

    return () => {
      mounted = false;
    };
  }, []);

  if (loading) {
    return <DownloadSkeleton />;
  }

  if (error || !release) {
    return <DownloadError />;
  }

  const checksumsAsset = findAssetByName(release, CHECKSUMS_ASSET_NAME);

  return (
    <div className={styles.wrapper}>
      <div className={styles.header}>
        <span className={styles.versionBadge}>{release.tag_name}</span>
        <a href={release.html_url} target="_blank" rel="noopener noreferrer" className={styles.releaseLink}>
          <Translate id="downloadSection.releaseNotes">Release notes →</Translate>
        </a>
      </div>
      <div className={styles.grid}>
        {PLATFORMS.map((platform) => (
          <PlatformCard
            key={platform.id}
            platform={platform}
            asset={findAssetByName(release, platform.assetName)}
            isDetected={platform.id === detectedPlatform}
          />
        ))}
      </div>
      {checksumsAsset && <ChecksumsLink checksumsAsset={checksumsAsset} />}
    </div>
  );
}
