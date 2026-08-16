// lib/features/events/presentation/event_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/itango_theme.dart';
import '../../../core/router/app_router.dart';
import '../domain/event_detail_models.dart';
import 'ticket_purchase_sheet.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventDetailProvider(eventId));

    return Scaffold(
      backgroundColor: ItangoColors.bgBase,
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: ItangoColors.brandPrimary)),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(ItangoSpacing.s6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Couldn't load this event.", style: TextStyle(color: ItangoColors.textPrimary)),
                const SizedBox(height: ItangoSpacing.s3),
                TextButton(
                  onPressed: () => ref.invalidate(eventDetailProvider(eventId)),
                  child: const Text('Retry', style: TextStyle(color: ItangoColors.brandPrimary)),
                ),
              ],
            ),
          ),
        ),
        data: (event) => _EventDetailBody(event: event),
      ),
    );
  }
}

class _EventDetailBody extends ConsumerWidget {
  const _EventDetailBody({required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 260,
          pinned: true,
          backgroundColor: ItangoColors.bgBase,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                event.coverUrl != null
                    ? Image.network(event.coverUrl!, fit: BoxFit.cover)
                    : Container(color: ItangoColors.bgSurfaceElevated),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                ),
                if (event.status == 'live')
                  Positioned(
                    top: ItangoSpacing.s12,
                    left: ItangoSpacing.s4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s3, vertical: 4),
                      decoration: BoxDecoration(gradient: ItangoGradients.liveBadge, borderRadius: BorderRadius.circular(ItangoRadius.pill)),
                      child: const Text('LIVE NOW', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(ItangoSpacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: const TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 24, fontWeight: FontWeight.w700, color: ItangoColors.textPrimary)),
                const SizedBox(height: ItangoSpacing.s2),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, color: ItangoColors.textSecondary, size: 16),
                    const SizedBox(width: ItangoSpacing.s2),
                    Text(DateFormat('EEE, MMM d · h:mm a').format(event.startTime), style: const TextStyle(color: ItangoColors.textSecondary)),
                  ],
                ),
                if (event.venueName != null) ...[
                  const SizedBox(height: ItangoSpacing.s1),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: ItangoColors.textSecondary, size: 16),
                      const SizedBox(width: ItangoSpacing.s2),
                      Text('${event.venueName} · ${event.venueCity}', style: const TextStyle(color: ItangoColors.textSecondary)),
                    ],
                  ),
                ],
                const SizedBox(height: ItangoSpacing.s2),
                Row(
                  children: [
                    const Icon(Icons.people_alt_rounded, color: ItangoColors.accentEmerald, size: 16),
                    const SizedBox(width: ItangoSpacing.s2),
                    Text('${event.liveAttendeeCount} checked in', style: const TextStyle(color: ItangoColors.accentEmerald, fontWeight: FontWeight.w600)),
                  ],
                ),
                if (event.description != null) ...[
                  const SizedBox(height: ItangoSpacing.s4),
                  Text(event.description!, style: const TextStyle(color: ItangoColors.textPrimary, height: 1.5)),
                ],
                const SizedBox(height: ItangoSpacing.s6),
                _ActionSection(event: event),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The three mutually-exclusive states a user can be in relative to this
/// event: no ticket yet → has a ticket but hasn't checked in → checked in.
/// Each state gets exactly one primary action, to avoid decision paralysis
/// on what is, functionally, the highest-stakes screen in the app (it's
/// where money changes hands).
class _ActionSection extends ConsumerWidget {
  const _ActionSection({required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (event.userHasCheckedIn) {
      return Container(
        padding: const EdgeInsets.all(ItangoSpacing.s4),
        decoration: BoxDecoration(color: ItangoColors.bgSurface, borderRadius: BorderRadius.circular(ItangoRadius.lg)),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: ItangoColors.statusSuccess),
            const SizedBox(width: ItangoSpacing.s3),
            const Expanded(child: Text("You're checked in — event room unlocked", style: TextStyle(color: ItangoColors.textPrimary, fontWeight: FontWeight.w600))),
            TextButton(
              onPressed: () => context.push('/chats'),
              child: const Text('Open Chat', style: TextStyle(color: ItangoColors.brandPrimary)),
            ),
          ],
        ),
      );
    }

    if (event.hasValidTicket) {
      return Column(
        children: [
          ItangoGradientButton(
            label: 'Show My Ticket QR',
            icon: Icons.qr_code_rounded,
            onPressed: () => context.push(AppRoutes.eventTicketPath(event.id), extra: event),
          ),
          const SizedBox(height: ItangoSpacing.s3),
          OutlinedButton.icon(
            onPressed: () => context.push(
              AppRoutes.eventCheckInPath(event.id),
              extra: {'eventTitle': event.title},
            ),
            icon: const Icon(Icons.location_on_rounded, color: ItangoColors.textSecondary),
            label: const Text('No scanner? Check in with location', style: TextStyle(color: ItangoColors.textSecondary)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: ItangoColors.borderDefault),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ItangoRadius.pill)),
            ),
          ),
        ],
      );
    }

    if (event.tickets.every((t) => t.isSoldOut)) {
      return Container(
        padding: const EdgeInsets.all(ItangoSpacing.s4),
        decoration: BoxDecoration(color: ItangoColors.bgSurface, borderRadius: BorderRadius.circular(ItangoRadius.lg)),
        child: const Text('Sold out', style: TextStyle(color: ItangoColors.textSecondary, fontWeight: FontWeight.w600)),
      );
    }

    return ItangoGradientButton(
      label: 'Get Tickets',
      onPressed: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: ItangoColors.bgSurface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ItangoRadius.xl2))),
        builder: (_) => TicketPurchaseSheet(eventId: event.id, tickets: event.tickets),
      ).then((_) => ref.invalidate(eventDetailProvider(event.id))),
    );
  }
}
