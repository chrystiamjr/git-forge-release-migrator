import React from 'react';
import styles from '../index.module.css';

export default function DownloadSkeleton(): JSX.Element {
  return (
    <div className={styles.skeleton}>
      <div className={styles.skeletonBadge} />
      <div className={styles.skeletonGrid}>
        {[0, 1, 2, 3].map((index) => (
          <div key={index} className={styles.skeletonCard} />
        ))}
      </div>
    </div>
  );
}
