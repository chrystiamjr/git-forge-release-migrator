import React from 'react';
import Link from '@docusaurus/Link';
import Translate from '@docusaurus/Translate';
import type { HomePageStyles } from '../types';

type HeroSectionProps = {
  styles: HomePageStyles;
  tagline: string;
};

export default function HeroSection({ styles, tagline }: HeroSectionProps): JSX.Element {
  return (
    <section className={styles.hero}>
      <div className={styles.heroGlow} />
      <div className={styles.heroInner}>
        <span className={styles.kicker}>
          <Translate id="homepage.kicker">Open Source CLI</Translate>
        </span>
        <h1 className={styles.heroTitle}>
          <Translate id="homepage.hero.title">{'Move releases across Git forges '}</Translate>
          <span className={styles.heroAccent}>
            <Translate id="homepage.hero.titleAccent">without redoing work</Translate>
          </span>
        </h1>
        <p className={styles.heroSubtitle}>{tagline}</p>
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
  );
}
