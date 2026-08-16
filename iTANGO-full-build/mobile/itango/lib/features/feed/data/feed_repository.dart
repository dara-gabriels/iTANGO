// lib/features/feed/data/feed_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class FeedPost {
final String postId;
final String authorId;
final String username;
final String displayName;
final String? avatarUrl;
final String? eventId;
final String? caption;
final List mediaUrls;
final int likeCount;
final int commentCount;
final double distanceKm;
final DateTime createdAt;

FeedPost({
required this.postId,
required this.authorId,
required this.username,
required this.displayName,
this.avatarUrl,
this.eventId,
this.caption,
required this.mediaUrls,
required this.likeCount,
required this.commentCount,
required this.distanceKm,
required this.createdAt,
});

factory FeedPost.fromJson(Map<String, dynamic> json) {
return FeedPost(
postId: json['post_id'] as String,
authorId: json['author_id'] as String,
username: json['author_username'] as String,
displayName: json['author_display_name'] as String,
avatarUrl: json['author_avatar_url'] as String?,
eventId: json['event_id'] as String?,
caption: json['caption'] as String?,
mediaUrls: List.from(json['media_urls'] ?? []),
likeCount: json['like_count'] as int,
commentCount: json['comment_count'] as int,
distanceKm: (json['distance_km'] as num).toDouble(),
createdAt: DateTime.parse(json['created_at'] as String),
);
}
}

class FeedRepository {
FeedRepository(this._client);
final SupabaseClient _client;

/// Calls the 15km database location-fence RPC function to fetch local posts.
Future<List> fetchLocalizedFeed({
required double latitude,
required double longitude,
int limit = 20,
int offset = 0,
}) async {
final List response = await _client.rpc(
'get_localized_social_feed',
params: {
'p_lat': latitude,
'p_lng': longitude,
'p_limit': limit,
'p_offset': offset,
},
);

return response.map((json) => FeedPost.fromJson(json as Map<String, dynamic>)).toList();
}
}