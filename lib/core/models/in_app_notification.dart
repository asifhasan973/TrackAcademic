import 'package:cloud_firestore/cloud_firestore.dart';

class InAppNotification {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String message;
  final String courseId;
  final String entityId;
  final bool isRead;
  final DateTime? createdAt;
  final DateTime? readAt;

  const InAppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    required this.courseId,
    required this.entityId,
    required this.isRead,
    this.createdAt,
    this.readAt,
  });

  factory InAppNotification.fromMap(String id, Map<String, dynamic> data) {
    DateTime? parseTimestamp(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      }
      if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    return InAppNotification(
      id: id,
      userId: data['userId'] as String? ?? '',
      type: data['type'] as String? ?? '',
      title: data['title'] as String? ?? '',
      message: data['message'] as String? ?? '',
      courseId: data['courseId'] as String? ?? '',
      entityId: data['entityId'] as String? ?? '',
      isRead: data['isRead'] as bool? ?? false,
      createdAt: parseTimestamp(data['createdAt']),
      readAt: parseTimestamp(data['readAt']),
    );
  }

  InAppNotification copyWith({
    String? id,
    String? userId,
    String? type,
    String? title,
    String? message,
    String? courseId,
    String? entityId,
    bool? isRead,
    DateTime? createdAt,
    DateTime? readAt,
  }) {
    return InAppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      courseId: courseId ?? this.courseId,
      entityId: entityId ?? this.entityId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  String timeAgo({DateTime? clock}) {
    if (createdAt == null) {
      return '';
    }
    final now = clock ?? DateTime.now();
    final difference = now.difference(createdAt!);

    if (difference.isNegative || difference.inSeconds < 45) {
      return 'Just now';
    }
    if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return '${mins}m ago';
    }
    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '${hours}h ago';
    }
    if (difference.inDays == 1) {
      return 'Yesterday';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    }

    final d = createdAt!;
    return '${_monthName(d.month)} ${d.day}';
  }

  static String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (month >= 1 && month <= 12) {
      return months[month - 1];
    }
    return '';
  }
}
