import React from 'react';
import type { HomeFeature } from '../data/features';
import type { HomePageStyles } from '../types';

type FeaturesSectionProps = {
  styles: HomePageStyles;
  features: HomeFeature[];
};

export default function FeaturesSection({ styles, features }: FeaturesSectionProps): JSX.Element {
  return (
    <section className={styles.features}>
      <div className={styles.container}>
        <div className={styles.featureGrid}>
          {features.map((feature, index) => (
            <div
              key={feature.title}
              className={styles.featureCard}
              style={{ animationDelay: `${index * 0.1}s` }}
            >
              <div className={styles.featureIcon}>{feature.icon}</div>
              <h3 className={styles.featureTitle}>{feature.title}</h3>
              <p className={styles.featureDesc}>{feature.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
