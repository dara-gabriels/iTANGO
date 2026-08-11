// lib/features/notifications/presentation/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/itango_theme.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/notification_models.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsStreamProvider);
    final client = ref.watch(supabaseClientProvider);

    return Scaffold(
      backgroundColor: ItangoColors.bgBase,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () => markAllNotificationsRead(client, client.auth.currentUser!.id),
            child: const Text('Mark all read', style: TextStyle(color: ItangoColors.brandPrimary, fontSize: 13)),
          ),
        ],
      ),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator(color: ItangoColors.brandPrimary)),
        error: (_, __) => const Center(child: Text('Could not load notifications', style: TextStyle(color: ItangoColors.textSecondary))),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No notifications yet', style: TextStyle(color: ItangoColors.textSecondary)))
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final n = list[i];
                  return ListTile(
                    onTap: () => markNotificationRead(client, n.id),
                    tileColor: n.isUnread ? ItangoColors.brandPrimary.withOpacity(0.06) : null,
                    leading: CircleAvatar(
                      backgroundColor: ItangoColors.bgSurfaceElevated,
                      child: Icon(_iconFor(n.type), color: ItangoColors.brandPrimary, size: 18),
                    ),
                    title: Text(n.title, style: const TextStyle(color: ItangoColors.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ItangoColors.textSecondary)),
                    trailing: Text(DateFormat.jm().format(n.createdAt), style: const TextStyle(color: ItangoColors.textTertiary, fontSize: 11)),
                  );
                },
              ),
      ),
    );
  }

  IconData _iconFor(String type) => switch (type) {
        'new_message' => Icons.chat_bubble_rounded,
        'checkin_confirmed' => Icons.check_circle_rounded,
        'ticket_confirmed' => Icons.confirmation_number_rounded,
        'achievement_earned' => Icons.emoji_events_rounded,
        'new_follower' || 'friend_request' => Icons.person_add_rounded,
        'voucher_available' => Icons.card_giftcard_rounded,
        _ => Icons.notifications_rounded,
      };
}
