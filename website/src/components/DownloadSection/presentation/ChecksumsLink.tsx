import React from 'react';
import Translate from '@docusaurus/Translate';
import type { ReleaseAsset } from '../domain/release';
import styles from '../index.module.css';

type ChecksumsLinkProps = {
  checksumsAsset: ReleaseAsset;
};

export default function ChecksumsLink({ checksumsAsset }: ChecksumsLinkProps): JSX.Element {
  return (
    <div className={styles.checksumRow}>
      <a href={checksumsAsset.browser_download_url} className={styles.checksumLink}>
        ↓ checksums-sha256.txt
      </a>
      <span className={styles.checksumHint}>
        <Translate id="downloadSection.checksumHint">Verify your download with SHA256</Translate>
      </span>
    </div>
  );
}
