import 'dart:async';

/// How long one step of tearing voice down may take before the next goes
/// ahead without it.
const cleanupLimit = Duration(seconds: 3);

/// Runs one cleanup [step], waiting at most [limit]; an error or a native
/// call that never returns is let go, so the steps after it still run.
Future<void> cleanupStep(Future<void> Function() step,
    {Duration limit = cleanupLimit}) async {
  try {
    await step().timeout(limit);
  } catch (_) {/* given up on: the rest of the cleanup goes on */}
}
