export type Platform = {
  id: 'macos-silicon' | 'macos-intel' | 'linux' | 'windows';
  assetName: string;
  label: string;
  icon: string;
  hint: string;
};

export const PLATFORMS: Platform[] = [
  {
    id: 'macos-silicon',
    assetName: 'gfrm-macos-silicon.zip',
    label: 'macOS Apple Silicon',
    icon: '🍎',
    hint: 'M1 / M2 / M3',
  },
  {
    id: 'macos-intel',
    assetName: 'gfrm-macos-intel.zip',
    label: 'macOS Intel',
    icon: '🍎',
    hint: 'x86_64',
  },
  {
    id: 'linux',
    assetName: 'gfrm-linux.zip',
    label: 'Linux',
    icon: '🐧',
    hint: 'x86_64',
  },
  {
    id: 'windows',
    assetName: 'gfrm-windows.zip',
    label: 'Windows',
    icon: '🪟',
    hint: 'x86_64',
  },
];

export type PlatformId = Platform['id'];
