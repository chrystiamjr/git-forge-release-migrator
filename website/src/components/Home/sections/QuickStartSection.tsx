import React from 'react';
import Link from '@docusaurus/Link';
import Translate, { translate } from '@docusaurus/Translate';
import type { HomePageStyles } from '../types';

type QuickStartSectionProps = {
  styles: HomePageStyles;
};

export default function QuickStartSection({ styles }: QuickStartSectionProps): JSX.Element {
  const quickStartCode = translate({
    id: 'homepage.quickStart.terminalCode',
    message: `# macOS — extract and allow execution
unzip gfrm-macos-silicon.zip
chmod +x gfrm
xattr -d com.apple.quarantine gfrm

# Bootstrap your provider tokens once
./gfrm setup

# Run a migration
./gfrm migrate \\
  --source github:org/old-repo \\
  --target gitlab:group/new-repo`,
  });

  return (
    <section className={styles.quickStart}>
      <div className={styles.container}>
        <h2 className={styles.sectionTitle}>
          <Translate id="homepage.quickStart.title">Quick start</Translate>
        </h2>
        <p className={styles.sectionSubtitle}>
          <Translate id="homepage.quickStart.subtitle">
            Download, extract, and run your first migration in minutes.
          </Translate>
        </p>
        <div className={styles.terminal}>
          <div className={styles.terminalBar}>
            <span className={styles.dot} />
            <span className={styles.dot} />
            <span className={styles.dot} />
            <span className={styles.terminalTitle}>bash</span>
          </div>
          <pre className={styles.terminalCode}>{quickStartCode}</pre>
        </div>
        <div className={styles.readNext}>
          <Link to="/getting-started/install-and-verify" className={styles.readNextLink}>
            <Translate id="homepage.readNext.installAndVerify">Install and Verify →</Translate>
          </Link>
          <Link to="/getting-started/first-migration" className={styles.readNextLink}>
            <Translate id="homepage.readNext.firstMigration">First Migration →</Translate>
          </Link>
          <Link to="/intro" className={styles.readNextLink}>
            <Translate id="homepage.readNext.fullDocs">Full Documentation →</Translate>
          </Link>
        </div>
      </div>
    </section>
  );
}
