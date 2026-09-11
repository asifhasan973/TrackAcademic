import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:trackademic/core/models/in_app_notification.dart';

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

  /// Marks all unread notifications as read in bounded batches (up to 100 per batch).
  Future<int> markAllAsRead(String userId, {int maxCount = 100}) async {
    if (userId.isEmpty) return 0;
    final unreadSnapshot = await _itemsRef(
      userId,
    ).where('isRead', isEqualTo: false).limit(maxCount).get();

    if (unreadSnapshot.docs.isEmpty) {
      return 0;
    }

    final batch = _database.batch();
    for (final doc in unreadSnapshot.docs) {
      batch.update(doc.reference, {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return unreadSnapshot.docs.length;
  }
}
