export type ReleaseAsset = {
  name: string;
  browser_download_url: string;
  size: number;
};

export type Release = {
  tag_name: string;
  html_url: string;
  assets: ReleaseAsset[];
};
