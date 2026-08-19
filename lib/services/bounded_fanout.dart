import 'dart:async';
import 'dart:collection';

/// Runs [fetch] over [candidates] with at most [concurrency] requests in
/// flight, collecting the answers that are not null.
///
/// [isCurrent] is consulted before each item is taken and again before its
/// result is kept, so a service torn down mid-flight abandons the work instead
/// of publishing it against a caller that has moved on. That check is the
/// fiddliest part of a bounded fetch and the reason this lives in one place:
/// every section that talks to Steam needs exactly this shape, and a copy that
/// forgets one of the two checks fails only under a race.
Future<List<R>> collectBounded<T, R>(
  Iterable<T> candidates, {
  required int concurrency,
  required bool Function() isCurrent,
  required Future<R?> Function(T candidate) fetch,
}) async {
  final collected = <R>[];
  final queue = Queue<T>.of(candidates);

  Future<void> worker() async {
    while (queue.isNotEmpty) {
      if (!isCurrent()) {
        return;
      }
      final result = await fetch(queue.removeFirst());
      if (result != null && isCurrent()) {
        collected.add(result);
      }
    }
  }

  await Future.wait(<Future<void>>[
    for (var i = 0; i < concurrency; i++) worker(),
  ]);
  return collected;
}
