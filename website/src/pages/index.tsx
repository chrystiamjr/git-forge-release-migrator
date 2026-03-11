import React from 'react';
import Layout from '@theme/Layout';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Translate, { translate } from '@docusaurus/Translate';
import DownloadSection from '../components/DownloadSection';
import styles from './index.module.css';

export default function Home(): JSX.Element {
  const { siteConfig } = useDocusaurusContext();

  const features = [
    {
      icon: '🔀',
      title: translate({
        id: 'homepage.feature.crossForge.title',
        message: 'Cross-forge migrations',
      }),
      description: translate({
        id: 'homepage.feature.crossForge.description',
        message:
          'Migrate between GitHub, GitLab, and Bitbucket Cloud in any direction. One command covers tags, releases, notes, and binary assets.',
      }),
    },
    {
      icon: '🔄',
      title: translate({
        id: 'homepage.feature.resilient.title',
        message: 'Resilient by design',
      }),
      description: translate({
        id: 'homepage.feature.resilient.description',
        message:
          'Checkpoint state is written to disk on every step. Interrupted runs resume exactly where they left off with gfrm resume.',
      }),
    },
    {
      icon: '📦',
      title: translate({
        id: 'homepage.feature.zeroDeps.title',
        message: 'Zero runtime dependencies',
      }),
      description: translate({
        id: 'homepage.feature.zeroDeps.description',
        message:
          'Ships as a single compiled binary. No Dart, Node, FVM, or Yarn required on the target machine.',
      }),
    },
  ];

  return (
    <Layout title={siteConfig.title} description={siteConfig.tagline}>
      {/* Hero */}
      <section className={styles.hero}>
        <div className={styles.heroGlow} />
        <div className={styles.heroInner}>
          <span className={styles.kicker}>
            <Translate id="homepage.kicker">Open Source CLI</Translate>
          </span>
          <h1 className={styles.heroTitle}>
            <Translate id="homepage.hero.title">
              {'Move releases across Git forges '}
            </Translate>
            <span className={styles.heroAccent}>
              <Translate id="homepage.hero.titleAccent">
                without redoing work
              </Translate>
            </span>
          </h1>
          <p className={styles.heroSubtitle}>{siteConfig.tagline}</p>
          <div className={styles.heroCtas}>
            <Link to="/intro" className={styles.ctaPrimary}>
              <Translate id="homepage.cta.getStarted">Get Started</Translate>
            </Link>
            <a href="#download" className={styles.ctaSecondary}>
              <Translate id="homepage.cta.download">Download</Translate>
            </a>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className={styles.features}>
        <div className={styles.container}>
          <div className={styles.featureGrid}>
            {features.map((f, i) => (
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

      {/* Quick start terminal */}
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
            <pre className={styles.terminalCode}>{translate({
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
            })}</pre>
          </div>
          <div className={styles.readNext}>
            <Link
              to="/getting-started/install-and-verify"
              className={styles.readNextLink}
            >
              <Translate id="homepage.readNext.installAndVerify">
                Install and Verify →
              </Translate>
            </Link>
            <Link
              to="/getting-started/first-migration"
              className={styles.readNextLink}
            >
              <Translate id="homepage.readNext.firstMigration">
                First Migration →
              </Translate>
            </Link>
            <Link to="/intro" className={styles.readNextLink}>
              <Translate id="homepage.readNext.fullDocs">
                Full Documentation →
              </Translate>
            </Link>
          </div>
        </div>
      </section>
    </Layout>
  );
}
