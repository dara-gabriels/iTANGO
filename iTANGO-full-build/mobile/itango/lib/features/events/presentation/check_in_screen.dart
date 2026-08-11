// lib/features/events/presentation/check_in_screen.dart
//
// DESIGN NOTE — why geofence, not QR scanning, is the primary flow HERE:
// The `/checkins` Edge Function (Phase 5) accepts qr_token bound to
// (eventId, userId, ticketPurchaseId) and signed at purchase time — that
// token lives on the TICKET HOLDER's own device/ticket, meant to be shown
// TO staff, not scanned BY the attendee. Staff-scans-attendee IS built —
// see backend/supabase/functions/staff-checkin/index.ts and the organizer
// web dashboard's Door Check-In scanner
// (web/itango-web/src/app/organizer/events/[eventId]/checkin/) — it's just
// not this consumer screen's job. For the consumer app, geofence
// self-check-in (already fully supported server-side) is the correct flow:
// the attendee opens the app at the venue and confirms presence via GPS,
// no organizer hardware required on their end.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/itango_theme.dart';
import '../domain/event_detail_models.dart';

class CheckInScreen extends ConsumerWidget {
  const CheckInScreen({super.key, required this.eventId, required this.eventTitle});
  final String eventId;
  final String eventTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkInState = ref.watch(checkInControllerProvider);

    ref.listen(checkInControllerProvider, (previous, next) {
      if (next is CheckInFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.message), backgroundColor: ItangoColors.statusDanger),
        );
      }
    });

    return Scaffold(
      backgroundColor: ItangoColors.bgBase,
      appBar: AppBar(title: const Text('Check In')),
      body: Padding(
        padding: const EdgeInsets.all(ItangoSpacing.s6),
        child: switch (checkInState) {
          CheckInSucceeded(:final energyAwarded, :final chatRoomConversationId) =>
            _SuccessView(energyAwarded: energyAwarded, onOpenChat: () {
              if (chatRoomConversationId != null) {
                context.go('/chats/$chatRoomConversationId');
              } else {
                context.go('/chats');
              }
            }),
          CheckInSubmitting() => const Center(child: CircularProgressIndicator(color: ItangoColors.brandPrimary)),
          _ => _PromptView(
              eventTitle: eventTitle,
              onCheckIn: () => ref.read(checkInControllerProvider.notifier).checkIn(eventId),
            ),
        },
      ),
    );
  }
}

class _PromptView extends StatelessWidget {
  const _PromptView({required this.eventTitle, required this.onCheckIn});
  final String eventTitle;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.location_on_rounded, color: ItangoColors.brandPrimary, size: 64),
        const SizedBox(height: ItangoSpacing.s5),
        Text(
          "Check in to $eventTitle",
          style: const TextStyle(color: ItangoColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ItangoSpacing.s2),
        const Text(
          "We'll confirm you're at the venue using your location. This unlocks the event's chat room and earns you Energy Score.",
          style: TextStyle(color: ItangoColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ItangoSpacing.s6),
        ItangoGradientButton(label: "I'm Here — Check In", icon: Icons.check_circle_outline, onPressed: onCheckIn),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.energyAwarded, required this.onOpenChat});
  final int energyAwarded;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.celebration_rounded, color: ItangoColors.statusSuccess, size: 64),
        const SizedBox(height: ItangoSpacing.s5),
        const Text("You're in the room! 🎉", style: TextStyle(color: ItangoColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: ItangoSpacing.s2),
        Text(
          "Chat unlocked because you checked in at this event. +$energyAwarded Energy Score.",
          style: const TextStyle(color: ItangoColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ItangoSpacing.s6),
        ItangoGradientButton(label: 'Open Event Chat', onPressed: onOpenChat),
      ],
    );
  }
}
