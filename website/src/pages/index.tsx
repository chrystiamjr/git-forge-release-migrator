import React from 'react';
import Layout from '@theme/Layout';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import { buildHomeFeatures } from '../components/Home/data/features';
import DownloadSectionBlock from '../components/Home/sections/DownloadSectionBlock';
import FeaturesSection from '../components/Home/sections/FeaturesSection';
import HeroSection from '../components/Home/sections/HeroSection';
import QuickStartSection from '../components/Home/sections/QuickStartSection';
import styles from './index.module.css';

export default function Home(): JSX.Element {
  const { siteConfig } = useDocusaurusContext();
  const features = buildHomeFeatures();

  return (
    <Layout title={siteConfig.title} description={siteConfig.tagline} wrapperClassName="gfrm-landing">
      <HeroSection styles={styles} tagline={siteConfig.tagline} />
      <FeaturesSection styles={styles} features={features} />
      <DownloadSectionBlock styles={styles} />
      <QuickStartSection styles={styles} />
    </Layout>
  );
}
