import React from 'react';
import Translate from '@docusaurus/Translate';
import styles from '../index.module.css';

export default function DownloadError(): JSX.Element {
  return (
    <div className={styles.errorBox}>
      <p>
        <Translate id="downloadSection.error.message">Could not load release information.</Translate>
      </p>
      <a
        href="https://github.com/chrystiamjr/git-forge-release-migrator/releases"
        target="_blank"
        rel="noopener noreferrer"
        className={styles.fallbackLink}
      >
        <Translate id="downloadSection.error.fallbackLink">View all releases on GitHub →</Translate>
      </a>
    </div>
  );
}
