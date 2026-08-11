// lib/features/discover/domain/discover_person.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/supabase/supabase_providers.dart';

/// Mirrors the `vibe_tag_name` Postgres enum (migration 001). Kept as a
/// Dart enum rather than a raw string so filter chips and the RPC call
/// can't drift from the database's allowed values.
enum VibeTag {
  turnt('turnt', 'Turnt', '🔥'),
  chill('chill', 'Chill', '😎'),
  networking('networking', 'Networking', '💼'),
  dancing('dancing', 'Dancing', '💃'),
  foodie('foodie', 'Foodie', '🍽️'),
  musicLover('music_lover', 'Music Lover', '🎧');

  const VibeTag(this.dbValue, this.label, this.emoji);
  final String dbValue;
  final String label;
  final String emoji;
}

class DiscoverPerson {
  DiscoverPerson({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.energyScore,
    required this.distanceKm,
    required this.vibeTags,
    required this.mutualEventCount,
  });

  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final int energyScore;
  final double distanceKm;
  final List<String> vibeTags;
  final int mutualEventCount;

  factory DiscoverPerson.fromRow(Map<String, dynamic> row) => DiscoverPerson(
        userId: row['user_id'] as String,
        username: row['username'] as String,
        displayName: row['display_name'] as String,
        avatarUrl: row['avatar_url'] as String?,
        energyScore: row['energy_score'] as int,
        distanceKm: (row['distance_km'] as num).toDouble(),
        vibeTags: (row['vibe_tags'] as List?)?.map((t) => t.toString()).toList() ?? [],
        mutualEventCount: (row['mutual_event_count'] as num?)?.toInt() ?? 0,
      );
}

/// Currently selected filter chip — null means "All".
final selectedVibeTagProvider = StateProvider<VibeTag?>((ref) => null);

final discoverPeopleProvider = FutureProvider.autoDispose<List<DiscoverPerson>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final selectedTag = ref.watch(selectedVibeTagProvider);

  final permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    await Geolocator.requestPermission();
  }
  final position = await Geolocator.getCurrentPosition();

  final rows = await client.rpc('discover_people', params: {
    'p_user_id': client.auth.currentUser!.id,
    'p_lat': position.latitude,
    'p_lng': position.longitude,
    'p_vibe_tag': selectedTag?.dbValue,
    'p_radius_km': 5,
    'p_limit': 30,
  });

  return (rows as List).map((r) => DiscoverPerson.fromRow(r as Map<String, dynamic>)).toList();
});
