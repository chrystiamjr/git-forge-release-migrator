/// Retry-command expectation for the smoke artifact contract.
enum RetryExpectation {
  /// `summary.retry_command` must be empty or missing.
  empty,

  /// `summary.retry_command` must be present and start with `gfrm resume`.
  nonempty,

  /// Either presence or absence is acceptable, but present commands are checked.
  any,
}
