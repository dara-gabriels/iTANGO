// lib/features/chat/domain/story_models.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';

class StorySummary {
  StorySummary({
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.hasUnviewedStory,
  });

  final String userId;
  final String username;
  final String? avatarUrl;
  final bool hasUnviewedStory;
}

/// Active (non-expired) stories from people the current user follows or is
/// friends with, grouped by user (one ring per person, matching the
/// confirmed Stories row). `expires_at > now()` mirrors the RLS policy on
/// `stories` (migration 010) — this query would return nothing extra even
/// if that filter were omitted, but keeping it explicit avoids relying on
/// the client trusting the server to have already filtered.
final activeStoriesProvider = FutureProvider.autoDispose<List<StorySummary>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser!.id;

  final rows = await client
      .from('stories')
      .select('''
        user_id,
        profiles!inner ( username, avatar_url ),
        story_views!left ( viewer_id )
      ''')
      .gt('expires_at', DateTime.now().toIso8601String())
      .or('user_id.eq.$userId,user_id.in.(${await _followedUserIdsSubquery(client, userId)})')
      .order('created_at', ascending: false);

  // Group by user_id — a user may have multiple active stories, but the row
  // shows one ring per person.
  final seen = <String>{};
  final result = <StorySummary>[];
  for (final row in rows as List) {
    final uid = row['user_id'] as String;
    if (!seen.add(uid)) continue;

    final profile = row['profiles'] as Map<String, dynamic>;
    final views = (row['story_views'] as List?) ?? [];
    final hasViewed = views.any((v) => v['viewer_id'] == userId);

    result.add(StorySummary(
      userId: uid,
      username: profile['username'] as String,
      avatarUrl: profile['avatar_url'] as String?,
      hasUnviewedStory: !hasViewed,
    ));
  }
  return result;
});

/// Two-step lookup (fetch followed IDs, then filter stories) rather than a
/// single joined query — PostgREST's `.in.()` filter needs a literal list,
/// not a nested subquery. Fine at MVP scale; if this becomes a hot path,
/// promote it to a `active_stories_for_user()` SQL function (same pattern
/// as `nearby_events`/`discover_people` in migration 011) so it's one
/// round-trip instead of two.
Future<String> _followedUserIdsSubquery(dynamic client, String userId) async {
  final rows = await client.from('follows').select('following_id').eq('follower_id', userId);
  final ids = (rows as List).map((r) => r['following_id'] as String).toList();
  return ids.isEmpty ? "''" : ids.join(',');
}

class HighlightCollection {
  HighlightCollection({required this.name, required this.coverUrl});
  final String name;
  final String? coverUrl;
}

final storyHighlightsProvider = FutureProvider.autoDispose<List<HighlightCollection>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser!.id;

  final rows = await client
      .from('stories')
      .select('highlight_collection, media_url')
      .eq('user_id', userId)
      .eq('is_highlight', true)
      .order('created_at', ascending: false);

  final byCollection = <String, String?>{};
  for (final row in rows as List) {
    final name = row['highlight_collection'] as String?;
    if (name == null) continue;
    byCollection.putIfAbsent(name, () => row['media_url'] as String?);
  }

  return byCollection.entries.map((e) => HighlightCollection(name: e.key, coverUrl: e.value)).toList();
});
