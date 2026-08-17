// lib/features/home/presentation/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/itango_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../notifications/domain/notification_models.dart';
import '../../feed/data/feed_repository.dart';
import '../../feed/presentation/feed_post_card.dart';

/// Model for a single row returned by the `nearby_events` Postgres function
/// (Phase 4/5). Kept minimal — full ticket/venue detail is fetched on the
/// event detail screen, not duplicated here.
class NearbyEvent {
  NearbyEvent({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.status,
    required this.distanceKm,
    required this.liveAttendeeCount,
  });

  final String id;
  final String title;
  final String? coverUrl;
  final String status;
  final double distanceKm;
  final int liveAttendeeCount;

  factory NearbyEvent.fromRow(Map<String, dynamic> row) => NearbyEvent(
        id: row['event_id'] as String,
        title: row['title'] as String,
        coverUrl: row['cover_url'] as String?,
        status: row['status'] as String,
        distanceKm: (row['distance_km'] as num).toDouble(),
        liveAttendeeCount: row['live_attendee_count'] as int,
      );
}

final nearbyEventsProvider = FutureProvider.autoDispose<List<NearbyEvent>>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  final permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    await Geolocator.requestPermission();
  }
  final position = await Geolocator.getCurrentPosition();

  final rows = await client.rpc('nearby_events', params: {
    'p_lat': position.latitude,
    'p_lng': position.longitude,
    'p_radius_km': 10,
    'p_limit': 20,
  });

  return (rows as List).map((r) => NearbyEvent.fromRow(r as Map<String, dynamic>)).toList();
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearbyEvents = ref.watch(nearbyEventsProvider);
    final localizedFeed = ref.watch(localizedFeedProvider);

    return Scaffold(
      backgroundColor: ItangoColors.bgBase,
      appBar: AppBar(
        title: const Text('iTANGO', style: TextStyle(fontFamily: 'PlayfairDisplay', fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: ItangoSpacing.s4),
            child: _NotificationBell(unreadCount: ref.watch(unreadNotificationCountProvider)),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: ItangoColors.brandPrimary,
        onRefresh: () async {
          ref.invalidate(nearbyEventsProvider);
          ref.invalidate(localizedFeedProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(ItangoSpacing.s4),
          children: [
            // Section 1: Nearby Live Events Component Row
            Text('Live Events Happening Now', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: ItangoSpacing.s3),
            nearbyEvents.when(
              loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: ItangoColors.brandPrimary))),
              error: (err, _) => _ErrorCard(message: "Couldn't load nearby events.", onRetry: () => ref.invalidate(nearbyEventsProvider)),
              data: (events) {
                if (events.isEmpty) {
                  return Container(
                    height: 100,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: ItangoColors.bgSurface, borderRadius: BorderRadius.circular(ItangoRadius.lg)),
                    child: const Text("No events nearby right now.", style: TextStyle(color: ItangoColors.textSecondary, fontSize: 13)),
                  );
                }
                return SizedBox(
                  height: 220,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const SizedBox(width: ItangoSpacing.s3),
                    itemBuilder: (_, i) => _EventCard(event: events[i]),
                  ),
                );
              },
            ),

            const SizedBox(height: ItangoSpacing.s6),

            // Section 2: Blended Proximity Social Feed System
            Text('What\'s Happening Near You', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: ItangoSpacing.s3),
            localizedFeed.when(
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(ItangoSpacing.s5), child: CircularProgressIndicator(color: ItangoColors.brandPrimary))),
              error: (err, _) => _ErrorCard(message: "Couldn't load your feed.", onRetry: () => ref.invalidate(localizedFeedProvider)),
              data: (posts) {
                if (posts.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(ItangoSpacing.s6),
                    alignment: Alignment.center,
                    child: const Text("Nothing posted in your 15km bubble yet. Be the first to share!", style: TextStyle(color: ItangoColors.textSecondary), textAlign: TextAlign.center),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(), // Delegates scroll controls to the parent container
                  itemCount: posts.length,
                  itemBuilder: (_, i) => FeedPostCard(post: posts[i]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.unreadCount});
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.notifications),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_rounded),
          if (unreadCount > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: const BoxDecoration(color: ItangoColors.statusLive, shape: BoxShape.circle),
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final NearbyEvent event;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.eventDetailPath(event.id)),
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ItangoRadius.lg),
          color: ItangoColors.bgSurface,
          image: event.coverUrl != null
              ? DecorationImage(image: NetworkImage(event.coverUrl!), fit: BoxFit.cover)
              : null,
        ),
        child: Stack(
          children: [
            if (event.status == 'live')
              Positioned(
                top: ItangoSpacing.s2,
                left: ItangoSpacing.s2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s2, vertical: 2),
                  decoration: BoxDecoration(gradient: ItangoGradients.liveBadge, borderRadius: BorderRadius.circular(ItangoRadius.pill)),
                  child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            Positioned(
              left: ItangoSpacing.s3,
              right: ItangoSpacing.s3,
              bottom: ItangoSpacing.s3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${event.distanceKm.toStringAsFixed(1)} km · ${event.liveAttendeeCount} here',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ItangoSpacing.s4),
      decoration: BoxDecoration(color: ItangoColors.bgSurface, borderRadius: BorderRadius.circular(ItangoRadius.lg)),
      child: Row(
        children: [
          Expanded(child: Text(message, style: const TextStyle(color: ItangoColors.textPrimary, fontSize: 13))),
          TextButton(onPressed: onRetry, child: const Text('Retry', style: TextStyle(color: ItangoColors.brandPrimary, fontSize: 13))),
        ],
      ),
    );
  }
}
