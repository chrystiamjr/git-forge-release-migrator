import { translate } from '@docusaurus/Translate';

export type HomeFeature = {
  icon: string;
  title: string;
  description: string;
};

type TranslateLike = (options: { id: string; message: string }) => string;

export function buildHomeFeatures(t: TranslateLike = translate): HomeFeature[] {
  return [
    {
      icon: '🔀',
      title: t({
        id: 'homepage.feature.crossForge.title',
        message: 'Cross-forge migrations',
      }),
      description: t({
        id: 'homepage.feature.crossForge.description',
        message:
          'Migrate between GitHub, GitLab, and Bitbucket Cloud in any direction. One command covers tags, releases, notes, and binary assets.',
      }),
    },
    {
      icon: '🔄',
      title: t({
        id: 'homepage.feature.resilient.title',
        message: 'Resilient by design',
      }),
      description: t({
        id: 'homepage.feature.resilient.description',
        message:
          'Checkpoint state is written to disk on every step. Interrupted runs resume exactly where they left off with gfrm resume.',
      }),
    },
    {
      icon: '📦',
      title: t({
        id: 'homepage.feature.zeroDeps.title',
        message: 'Zero runtime dependencies',
      }),
      description: t({
        id: 'homepage.feature.zeroDeps.description',
        message:
          'Ships as a single compiled binary. No Dart, Node, FVM, or Yarn required on the target machine.',
      }),
    },
  ];
}
