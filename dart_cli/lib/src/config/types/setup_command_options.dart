class SetupCommandOptions {
  const SetupCommandOptions({
    required this.profile,
    required this.localScope,
    required this.assumeYes,
    required this.force,
  });

  final String profile;
  final bool localScope;
  final bool assumeYes;
  final bool force;
}
