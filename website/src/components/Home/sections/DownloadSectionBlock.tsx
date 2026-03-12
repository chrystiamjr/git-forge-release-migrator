import React from 'react';
import Translate from '@docusaurus/Translate';
import DownloadSection from '../../DownloadSection';
import type { HomePageStyles } from '../types';

type DownloadSectionBlockProps = {
  styles: HomePageStyles;
};

export default function DownloadSectionBlock({ styles }: DownloadSectionBlockProps): JSX.Element {
  return (
    <section id="download" className={styles.downloadSection}>
      <div className={styles.container}>
        <h2 className={styles.sectionTitle}>
          <Translate id="homepage.download.title">Download</Translate>
        </h2>
        <p className={styles.sectionSubtitle}>
          <Translate id="homepage.download.subtitle">
            Pre-compiled binaries for all platforms. No runtime required.
          </Translate>
        </p>
        <DownloadSection />
      </div>
    </section>
  );
}
