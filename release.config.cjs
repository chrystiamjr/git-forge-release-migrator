const preMajorReleaseRules = [
  // Pre-1.0 policy: keep breaking changes as minor while bootstrapping releases.
  // Remove this rule when the project reaches v1.0.0 so major bumps work normally.
  { breaking: true, release: "minor" },
  { revert: true, release: "patch" },
  { type: "feat", release: "minor" },
  { type: "fix", release: "patch" },
  { type: "perf", release: "patch" },
  { type: "refactor", release: "patch" },
  { type: "docs", release: "patch" },
  { type: "chore", release: "patch" },
  { type: "build", release: "patch" },
  { type: "ci", release: "patch" },
  { type: "test", release: "patch" },
  { type: "style", release: "patch" },
];

module.exports = {
  branches: ["main"],
  tagFormat: "v${version}",
  plugins: [
    [
      "@semantic-release/commit-analyzer",
      {
        preset: "conventionalcommits",
        releaseRules: preMajorReleaseRules,
      },
    ],
    ["@semantic-release/release-notes-generator", { preset: "conventionalcommits" }],
    ["@semantic-release/changelog", { changelogFile: "CHANGELOG.md" }],
    [
      "@semantic-release/git",
      {
        assets: ["CHANGELOG.md"],
        message: "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}",
      },
    ],
    [
      "@semantic-release/github",
      {
        successComment: false,
        failComment: false,
        releasedLabels: false,
      },
    ],
  ],
};
