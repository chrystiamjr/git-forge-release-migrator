enum MigrationProviderOption {
  github('github', 'GitHub'),
  gitlab('gitlab', 'GitLab'),
  bitbucket('bitbucket', 'Bitbucket');

  const MigrationProviderOption(this.id, this.label);

  final String id;
  final String label;
}
