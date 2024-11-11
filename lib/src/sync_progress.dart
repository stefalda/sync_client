// Example usage
// final repository = SyncRepository(...);
// repository.syncProgress.listen((progress) {
//   switch(progress.status) {
//     case SyncStatus.starting:
//       print('Sync started');
//       break;
//     case SyncStatus.pulling:
//       print('Pulling: ${progress.processedItems}/${progress.totalItems}');
//       break;
//     case SyncStatus.pushing:
//       print('Pushing: ${progress.processedItems}');
//       break;
//     case SyncStatus.completed:
//       print('Sync completed!');
//       break;
//     case SyncStatus.error:
//       print('Error: ${progress.error}');
//       break;
//   }
// });
enum SyncStatus { starting, pulling, pushing, completed, error }

class SyncProgress {
  final SyncStatus status;
  final String message;
  final int? processedItems;
  final int? totalItems;
  final String? error;

  SyncProgress({
    required this.status,
    required this.message,
    this.processedItems,
    this.totalItems,
    this.error,
  });

  double? get progress {
    if (processedItems == null || totalItems == null) return null;
    return processedItems! / totalItems!;
  }
}
