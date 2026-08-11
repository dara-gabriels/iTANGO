// lib/features/stories/domain/story_viewer_models.dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

class StoryItem {
  StoryItem({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.mediaType,
    required this.caption,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String mediaUrl;
  final String mediaType; // 'image' | 'video'
  final String? caption;
  final DateTime createdAt;

  factory StoryItem.fromRow(Map<String, dynamic> row) => StoryItem(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        mediaUrl: row['media_url'] as String,
        mediaType: row['media_type'] as String? ?? 'image',
        caption: row['caption'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}

/// All of one user's active stories, oldest first (viewed in chronological
/// order, matching how Snapchat/Instagram present a single person's story set).
final userStoriesProvider = FutureProvider.autoDispose.family<List<StoryItem>, String>((ref, userId) async {
  final client = ref.watch(supabaseClientProvider);

  final rows = await client
      .from('stories')
      .select('id, user_id, media_url, media_type, caption, created_at')
      .eq('user_id', userId)
      .gt('expires_at', DateTime.now().toIso8601String())
      .eq('is_highlight', false) // the Stories row shows active stories; Highlights are browsed separately
      .order('created_at', ascending: true);

  return (rows as List).map((r) => StoryItem.fromRow(r as Map<String, dynamic>)).toList();
});

Future<void> markStoryViewed(SupabaseClient client, String storyId) async {
  final userId = client.auth.currentUser?.id;
  if (userId == null) return;

  await client.from('story_views').upsert(
    {'story_id': storyId, 'viewer_id': userId},
    onConflict: 'story_id,viewer_id',
  );
}

/// Uploads a locally-captured file to the `story-media` Storage bucket and
/// returns its public URL, for use as `createStory`'s `mediaUrl` argument.
///
/// ASSUMES a public `story-media` bucket already exists on the Supabase
/// project (Storage → New bucket → public). Not created by this code —
/// bucket creation + its own access policy is a one-time manual/Terraform-
/// adjacent setup step, same category as the Supabase project setup in
/// devops/scripts/setup-supabase-projects.md, which this should be added to.
Future<String> uploadStoryMedia(SupabaseClient client, File file, {required String mediaType}) async {
  final userId = client.auth.currentUser!.id;
  final extension = mediaType == 'video' ? 'mp4' : 'jpg';
  final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';

  await client.storage.from('story-media').upload(path, file);
  return client.storage.from('story-media').getPublicUrl(path);
}

/// Creates a new story. `highlightCollection` is optional — when provided,
/// the story is saved as a highlight immediately rather than only living
/// for 24 hours (matches the confirmed "Add to Story / Save to Highlights"
/// choice from the original Figma flow notes).
Future<void> createStory(
  SupabaseClient client, {
  required String mediaUrl,
  required String mediaType,
  String? caption,
  String? highlightCollection,
}) async {
  await client.from('stories').insert({
    'user_id': client.auth.currentUser!.id,
    'media_url': mediaUrl,
    'media_type': mediaType,
    'caption': caption,
    'is_highlight': highlightCollection != null,
    'highlight_collection': highlightCollection,
  });
}
