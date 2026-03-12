import React from 'react';
import Translate from '@docusaurus/Translate';
import type { Platform } from '../domain/platform';
import type { ReleaseAsset } from '../domain/release';
import { formatSize } from '../domain/size';
import styles from '../index.module.css';

type PlatformCardProps = {
  platform: Platform;
  asset?: ReleaseAsset;
  isDetected: boolean;
};

export default function PlatformCard({ platform, asset, isDetected }: PlatformCardProps): JSX.Element {
  return (
    <div className={`${styles.platformCard} ${isDetected ? styles.detected : ''}`}>
      {isDetected && (
        <span className={styles.detectedBadge}>
          <Translate id="downloadSection.detectedBadge">Your platform</Translate>
        </span>
      )}
      <div className={styles.platformIcon}>{platform.icon}</div>
      <div className={styles.platformInfo}>
        <strong>{platform.label}</strong>
        <span className={styles.platformHint}>{platform.hint}</span>
      </div>
      {asset ? (
        <a href={asset.browser_download_url} className={`${styles.downloadBtn} ${isDetected ? styles.downloadBtnPrimary : ''}`}>
          <Translate id="downloadSection.downloadButton">Download</Translate>
          <span className={styles.fileSize}>{formatSize(asset.size)}</span>
        </a>
      ) : (
        <span className={styles.unavailable}>
          <Translate id="downloadSection.unavailable">Unavailable</Translate>
        </span>
      )}
    </div>
  );
}
