import React from 'react';
import Layout from '@theme/Layout';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import DownloadSection from '../components/DownloadSection';
import styles from './index.module.css';

const FEATURES = [
  {
    icon: '🔀',
    title: 'Cross-forge migrations',
    description:
      'Migrate between GitHub, GitLab, and Bitbucket Cloud in any direction. One command covers tags, releases, notes, and binary assets.',
  },
  {
    icon: '🔄',
    title: 'Resilient by design',
    description:
      'Checkpoint state is written to disk on every step. Interrupted runs resume exactly where they left off with gfrm resume.',
  },
  {
    icon: '📦',
    title: 'Zero runtime dependencies',
    description:
      'Ships as a single compiled binary. No Dart, Node, FVM, or Yarn required on the target machine.',
  },
];

export default function Home(): JSX.Element {
  const { siteConfig } = useDocusaurusContext();

  return (
    <Layout title={siteConfig.title} description={siteConfig.tagline}>
      {/* Hero */}
      <section className={styles.hero}>
        <div className={styles.heroGlow} />
        <div className={styles.heroInner}>
          <span className={styles.kicker}>Open Source CLI</span>
          <h1 className={styles.heroTitle}>
            Move releases across Git forges{' '}
            <span className={styles.heroAccent}>without redoing work</span>
          </h1>
          <p className={styles.heroSubtitle}>{siteConfig.tagline}</p>
          <div className={styles.heroCtas}>
            <Link to="/intro" className={styles.ctaPrimary}>
              Get Started
            </Link>
            <a href="#download" className={styles.ctaSecondary}>
              Download
            </a>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className={styles.features}>
        <div className={styles.container}>
          <div className={styles.featureGrid}>
            {FEATURES.map((f, i) => (
              <div
                key={f.title}
                className={styles.featureCard}
                style={{ animationDelay: `${i * 0.1}s` }}
              >
                <div className={styles.featureIcon}>{f.icon}</div>
                <h3 className={styles.featureTitle}>{f.title}</h3>
                <p className={styles.featureDesc}>{f.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Download */}
      <section id="download" className={styles.downloadSection}>
        <div className={styles.container}>
          <h2 className={styles.sectionTitle}>Download</h2>
          <p className={styles.sectionSubtitle}>
            Pre-compiled binaries for all platforms. No runtime required.
          </p>
          <DownloadSection />
        </div>
      </section>

      {/* Quick start terminal */}
      <section className={styles.quickStart}>
        <div className={styles.container}>
          <h2 className={styles.sectionTitle}>Quick start</h2>
          <p className={styles.sectionSubtitle}>
            Download, extract, and run your first migration in minutes.
          </p>
          <div className={styles.terminal}>
            <div className={styles.terminalBar}>
              <span className={styles.dot} />
              <span className={styles.dot} />
              <span className={styles.dot} />
              <span className={styles.terminalTitle}>bash</span>
            </div>
            <pre className={styles.terminalCode}>{`# macOS — extract and allow execution
unzip gfrm-macos-silicon.zip
chmod +x gfrm
xattr -d com.apple.quarantine gfrm

# Bootstrap your provider tokens once
./gfrm setup

# Run a migration
./gfrm migrate \\
  --source github:org/old-repo \\
  --target gitlab:group/new-repo`}</pre>
          </div>
          <div className={styles.readNext}>
            <Link
              to="/getting-started/install-and-verify"
              className={styles.readNextLink}
            >
              Install and Verify →
            </Link>
            <Link
              to="/getting-started/first-migration"
              className={styles.readNextLink}
            >
              First Migration →
            </Link>
            <Link to="/intro" className={styles.readNextLink}>
              Full Documentation →
            </Link>
          </div>
        </div>
      </section>
    </Layout>
  );
}
