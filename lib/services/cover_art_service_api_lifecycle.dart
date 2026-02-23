part of 'cover_art_service.dart';

void _resetCoverArtApiQueueState() {
  while (_apiPermitQueue.isNotEmpty) {
    final waiter = _apiPermitQueue.removeFirst();
    if (waiter.isCompleted) {
      continue;
    }
    waiter.completeError(const _RetryableApiException());
  }
}
