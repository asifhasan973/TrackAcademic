import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:trackademic/core/models/in_app_notification.dart';

class MarkAllAsReadResult {
  final int count;
  final bool hasMore;

  const MarkAllAsReadResult({required this.count, required this.hasMore});
}

class NotificationService {
  const NotificationService();

  FirebaseFirestore get _database => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _itemsRef(String userId) {
    return _database
        .collection('notifications')
        .doc(userId)
        .collection('items');
  }

  /// Streams the unread notification count in real-time.
  Stream<int> streamUnreadCount(String userId) {
    if (userId.isEmpty) {
      return Stream.value(0);
    }
    return _itemsRef(userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Streams notifications ordered by createdAt descending (newest first).
  Stream<List<InAppNotification>> streamNotifications(
    String userId, {
    int limit = 50,
  }) {
    if (userId.isEmpty) {
      return Stream.value(const []);
    }
    return _itemsRef(userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => InAppNotification.fromMap(doc.id, doc.data()))
              .toList();
        });
  }

  /// Marks a single notification as read.
  Future<void> markAsRead(String userId, String notificationId) async {
    if (userId.isEmpty || notificationId.isEmpty) return;
    await _itemsRef(userId).doc(notificationId).update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks unread notifications as read in bounded batches (clamped between 1 and 100).
  /// Performs a bounded continuation loop up to [maxTotal] (default 500) and returns [MarkAllAsReadResult].
  Future<MarkAllAsReadResult> markAllAsRead(
    String userId, {
    int batchSize = 100,
    int maxTotal = 500,
  }) async {
    if (userId.isEmpty) {
      return const MarkAllAsReadResult(count: 0, hasMore: false);
    }

    final clampedBatchSize = batchSize.clamp(1, 100);
    final clampedMaxTotal = maxTotal < clampedBatchSize
        ? clampedBatchSize
        : maxTotal;

    int totalMarked = 0;
    bool hasMore = false;

    while (totalMarked < clampedMaxTotal) {
      final toFetch = (clampedMaxTotal - totalMarked).clamp(
        1,
        clampedBatchSize,
      );
      final unreadSnapshot = await _itemsRef(
        userId,
      ).where('isRead', isEqualTo: false).limit(toFetch + 1).get();

      if (unreadSnapshot.docs.isEmpty) {
        break;
      }

      final docsToUpdate = unreadSnapshot.docs.take(toFetch).toList();
      final batch = _database.batch();
      for (final doc in docsToUpdate) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      totalMarked += docsToUpdate.length;

      if (unreadSnapshot.docs.length > toFetch) {
        hasMore = true;
        break;
      }

      if (docsToUpdate.length < toFetch) {
        break;
      }
    }

    return MarkAllAsReadResult(count: totalMarked, hasMore: hasMore);
  }
}
