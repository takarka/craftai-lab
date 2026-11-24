import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/transfer_review.dart';
import 'infrastructure/transfer_review_store.dart';

final transferReviewStoreProvider = Provider<TransferReviewStore>(
  (ref) => const TransferReviewStore(),
);

final transferReviewProvider =
    AsyncNotifierProvider.family<
      TransferReviewController,
      TransferReview?,
      String
    >(TransferReviewController.new, retry: (count, error) => null);

class TransferReviewController extends AsyncNotifier<TransferReview?> {
  TransferReviewController(this.ownerId);
  final String ownerId;

  Future<void> _writes = Future<void>.value();

  @override
  Future<TransferReview?> build() =>
      ref.watch(transferReviewStoreProvider).read(ownerId);

  /// Serialize writes and read the current value at the start of each write.
  Future<void> change(TransferReview? Function(TransferReview?) edit) {
    final write = _writes.then((_) async {
      final previous = await future;
      final next = edit(previous);
      if (identical(previous, next)) return;
      final store = ref.read(transferReviewStoreProvider);
      if (next == null) {
        await store.clear(ownerId);
      } else {
        await store.write(ownerId, next);
      }
      if (ref.mounted) state = AsyncData(next);
    });
    _writes = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }
}
