enum RunStateLifecycle {
  idle('idle'),
  running('running'),
  completed('completed'),
  failed('failed');

  const RunStateLifecycle(this.value);

  final String value;
}
