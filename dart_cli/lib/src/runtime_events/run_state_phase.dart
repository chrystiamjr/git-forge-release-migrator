enum RunStatePhase {
  idle('idle'),
  preflight('preflight'),
  execution('execution'),
  tags('tags'),
  releases('releases'),
  artifactFinalization('artifact_finalization'),
  completed('completed');

  const RunStatePhase(this.value);

  final String value;
}
