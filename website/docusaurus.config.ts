import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
    title: 'Git Forge Release Migrator',
    tagline: 'Resilient cross-forge CLI for migrating tags, releases, notes, and assets',
    favicon: 'img/favicon.svg',
    url: 'https://chrystiamjr.github.io',
    baseUrl: '/git-forge-release-migrator/',
    organizationName: 'chrystiamjr',
    projectName: 'git-forge-release-migrator',
    trailingSlash: false,
    onBrokenLinks: 'throw',
    markdown: {
        hooks: {
            onBrokenMarkdownLinks: 'warn',
        },
    },
    stylesheets: [
        {
            href: 'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;700&family=IBM+Plex+Mono:wght@400;500&display=swap',
            type: 'text/css',
        },
    ],
    i18n: {
        defaultLocale: 'en',
        locales: ['en', 'pt-BR'],
        localeConfigs: {
            en: {label: 'English'},
            'pt-BR': {label: 'Português (Brasil)'},
        },
    },
    presets: [
        [
            'classic',
            {
                docs: {
                    sidebarPath: './sidebars.ts',
                    routeBasePath: '/',
                },
                blog: false,
                theme: {
                    customCss: './src/css/custom.css',
                },
            } satisfies Preset.Options,
        ],
    ],
    themeConfig: {
        navbar: {
            title: '',
            logo: {
                alt: 'gfrm logo',
                src: 'img/logo.svg',
                srcDark: 'img/logo-dark.svg',
                height: 28,
            },
            items: [
                {
                    type: 'docSidebar',
                    sidebarId: 'docs',
                    position: 'left',
                    label: 'Docs',
                },
                {
                    href: 'https://github.com/chrystiamjr/git-forge-release-migrator/releases',
                    label: 'Releases',
                    position: 'right',
                },
                {
                    href: 'https://github.com/chrystiamjr/git-forge-release-migrator',
                    label: 'GitHub',
                    position: 'right',
                },
                {
                    type: 'localeDropdown',
                    position: 'right',
                },
            ],
        },
        footer: {
            style: 'dark',
            links: [
                {
                    title: 'Start Here',
                    items: [
                        {label: 'Overview', to: '/'},
                        {label: 'Quick Start', to: '/getting-started/quick-start'},
                        {label: 'Install and Verify', to: '/getting-started/install-and-verify'},
                    ],
                },
                {
                    title: 'Commands',
                    items: [
                        {label: 'migrate', to: '/commands/migrate'},
                        {label: 'resume', to: '/commands/resume'},
                        {label: 'setup', to: '/commands/setup'},
                        {label: 'settings', to: '/commands/settings'},
                    ],
                },
                {
                    title: 'Project',
                    items: [
                        {label: 'Development', to: '/project/development'},
                        {label: 'Changelog', to: '/project/changelog'},
                        {label: 'GitHub', href: 'https://github.com/chrystiamjr/git-forge-release-migrator'},
                        {label: 'Releases', href: 'https://github.com/chrystiamjr/git-forge-release-migrator/releases'},
                    ],
                },
            ],
            copyright: `Copyright © ${new Date().getFullYear()} Git Forge Release Migrator. Built with Docusaurus.`,
        },
        prism: {
            theme: prismThemes.github,
            darkTheme: prismThemes.dracula,
            additionalLanguages: ['bash', 'powershell', 'yaml', 'json'],
        },
    } satisfies Preset.ThemeConfig,
};

export default config;
