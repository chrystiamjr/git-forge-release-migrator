import type { SidebarsConfig } from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docs: [
    {
      type: 'category',
      label: 'Start Here',
      items: [
        'intro',
        'getting-started/quick-start',
        'getting-started/install-and-verify',
        'getting-started/first-migration',
      ],
    },
    {
      type: 'category',
      label: 'Configuration',
      items: [
        'configuration/settings-profiles',
        'configuration/tokens-and-auth',
        'configuration/http-and-runtime',
        'configuration/artifacts-and-sessions',
      ],
    },
    {
      type: 'category',
      label: 'Commands',
      items: [
        'commands/migrate',
        'commands/resume',
        'commands/setup',
        'commands/settings',
        'commands/demo',
      ],
    },
    {
      type: 'category',
      label: 'Guides',
      items: [
        'guides/common-migrations',
        'guides/resume-and-retry',
        'guides/bitbucket-behavior',
        'guides/macos-release-artifacts',
      ],
    },
    {
      type: 'category',
      label: 'Reference',
      items: [
        'reference/support-matrix',
        'reference/exit-codes',
        'reference/environment-aliases',
        'reference/file-locations',
      ],
    },
    {
      type: 'category',
      label: 'Project',
      items: [
        'project/changelog',
        'project/development',
        'project/ci-and-release',
      ],
    },
  ],
};

export default sidebars;
