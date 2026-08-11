// lib/features/notifications/domain/notification_models.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';

class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.payload,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  factory AppNotification.fromRow(Map<String, dynamic> row) => AppNotification(
        id: row['id'] as String,
        type: row['type'] as String,
        payload: Map<String, dynamic>.from(row['payload'] as Map? ?? {}),
        readAt: row['read_at'] != null ? DateTime.parse(row['read_at'] as String) : null,
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  /// Mirrors the copy mapping in the backend's `send-push-notification`
  /// function (`NOTIFICATION_COPY`) — kept in sync manually since one lives
  /// in Dart and the other in Deno; a shared codegen source is a reasonable
  /// follow-up if these drift in practice.
  String get title => switch (type) {
        'new_message' => 'New message',
        'checkin_confirmed' => 'Checked in! 🎉',
        'ticket_confirmed' => 'Ticket confirmed',
        'achievement_earned' => 'Achievement unlocked 🏆',
        'new_follower' => 'New follower',
        'friend_request' => 'Friend request',
        'voucher_available' => 'New voucher',
        _ => 'Notification',
      };

  String get body => switch (type) {
        'new_message' => (payload['preview'] as String?) ?? 'You have a new message',
        'checkin_confirmed' => "You're in at ${payload['event_title'] ?? 'the event'} — chat unlocked.",
        'ticket_confirmed' => 'Your ticket is ready — see it in My Tickets.',
        'achievement_earned' => 'You earned "${payload['name']}"',
        'new_follower' => 'Someone started following you',
        'friend_request' => 'You have a new friend request',
        'voucher_available' => 'A new perk is waiting in your Voucher Wallet',
        _ => '',
      };
}

final notificationsStreamProvider = StreamProvider.autoDispose<List<AppNotification>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser!.id;

  return client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .map((rows) => rows.map((r) => AppNotification.fromRow(r)).toList());
});

final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notifications = ref.watch(notificationsStreamProvider);
  return notifications.maybeWhen(
    data: (list) => list.where((n) => n.isUnread).length,
    orElse: () => 0,
  );
});

Future<void> markNotificationRead(dynamic client, String notificationId) async {
  await client.from('notifications').update({'read_at': DateTime.now().toIso8601String()}).eq('id', notificationId);
}

Future<void> markAllNotificationsRead(dynamic client, String userId) async {
  await client.from('notifications').update({'read_at': DateTime.now().toIso8601String()}).eq('user_id', userId).isFilter('read_at', null);
}
