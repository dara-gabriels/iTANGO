// lib/features/chat/domain/chat_models.dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

enum ConversationType { dm, group, eventRoom }

ConversationType _typeFromDb(String value) => switch (value) {
      'dm' => ConversationType.dm,
      'group' => ConversationType.group,
      'event_room' => ConversationType.eventRoom,
      _ => ConversationType.dm,
    };

enum RoomTemperature { cold, warm, hot, onFire }

RoomTemperature _temperatureFromDb(String? value) => switch (value) {
      'warm' => RoomTemperature.warm,
      'hot' => RoomTemperature.hot,
      'on_fire' => RoomTemperature.onFire,
      _ => RoomTemperature.cold,
    };

class ConversationSummary {
  ConversationSummary({
    required this.conversationId,
    required this.type,
    required this.title,
    this.eventCoverUrl,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.liveAttendeeCount,
    this.temperature = RoomTemperature.cold,
    this.unreadCount = 0,
  });

  final String conversationId;
  final ConversationType type;
  final String title;
  final String? eventCoverUrl;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int? liveAttendeeCount; // only populated for event_room type
  final RoomTemperature temperature;
  final int unreadCount;
}

/// Event Rooms — conversations of type event_room the current user has
/// joined (via check-in, per the join_event_room_on_checkin trigger). Joins
/// against the latest room_engagement_snapshot for the "🔥 On Fire" /
/// "Heated" indicator, and against events for cover image + live count.
final eventRoomsProvider = FutureProvider.autoDispose<List<ConversationSummary>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser!.id;

  final rows = await client
      .from('conversation_participants')
      .select('''
        conversation_id,
        conversations!inner (
          id, type, title, event_id,
          events ( cover_url, live_attendee_count ),
          messages ( content, created_at ),
          room_engagement_snapshots ( temperature, window_start )
        )
      ''')
      .eq('user_id', userId)
      .eq('conversations.type', 'event_room')
      .order('created_at', ascending: false, referencedTable: 'conversations.messages')
      .limit(1, referencedTable: 'conversations.messages')
      .order('window_start', ascending: false, referencedTable: 'conversations.room_engagement_snapshots')
      .limit(1, referencedTable: 'conversations.room_engagement_snapshots');

  return (rows as List).map((row) {
    final conversation = row['conversations'] as Map<String, dynamic>;
    final event = conversation['events'] as Map<String, dynamic>?;
    final messages = (conversation['messages'] as List?) ?? [];
    final lastMessage = messages.isNotEmpty ? messages.first as Map<String, dynamic> : null;
    final snapshots = (conversation['room_engagement_snapshots'] as List?) ?? [];
    final latestSnapshot = snapshots.isNotEmpty ? snapshots.first as Map<String, dynamic> : null;

    return ConversationSummary(
      conversationId: conversation['id'] as String,
      type: _typeFromDb(conversation['type'] as String),
      title: conversation['title'] as String? ?? 'Event Room',
      eventCoverUrl: event?['cover_url'] as String?,
      liveAttendeeCount: event?['live_attendee_count'] as int?,
      lastMessagePreview: lastMessage?['content'] as String?,
      lastMessageAt: lastMessage != null ? DateTime.parse(lastMessage['created_at'] as String) : null,
      temperature: _temperatureFromDb(latestSnapshot?['temperature'] as String?),
    );
  }).toList();
});

/// Direct messages + group chats (non-event-room conversations).
final directConversationsProvider = FutureProvider.autoDispose<List<ConversationSummary>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser!.id;

  final rows = await client
      .from('conversation_participants')
      .select('''
        conversation_id,
        conversations!inner ( id, type, title )
      ''')
      .eq('user_id', userId)
      .neq('conversations.type', 'event_room');

  return (rows as List).map((row) {
    final conversation = row['conversations'] as Map<String, dynamic>;
    return ConversationSummary(
      conversationId: conversation['id'] as String,
      type: _typeFromDb(conversation['type'] as String),
      title: conversation['title'] as String? ?? 'Direct Message',
    );
  }).toList();
});

/// Finds an existing 1:1 DM between the current user and [otherUserId], or
/// creates one. Used by Discover's "Say Hi" and Profile's "Message" action
/// so both entry points converge on the same conversation rather than
/// creating duplicate DM threads.
Future<String> startOrGetDmConversation(SupabaseClient client, String otherUserId) async {
  final userId = client.auth.currentUser!.id;

  // Look for an existing DM shared by exactly these two participants.
  final existing = await client.rpc('find_dm_conversation', params: {
    'p_user_a': userId,
    'p_user_b': otherUserId,
  });

  if (existing != null) return existing as String;

  final newConversation = await client
      .from('conversations')
      .insert({'type': 'dm', 'created_by': userId})
      .select('id')
      .single();

  final conversationId = newConversation['id'] as String;

  await client.from('conversation_participants').insert([
    {'conversation_id': conversationId, 'user_id': userId},
    {'conversation_id': conversationId, 'user_id': otherUserId},
  ]);

  return conversationId;
}

/// Sends a short opener message into a (possibly just-created) DM.
Future<void> sendMessage(SupabaseClient client, {required String conversationId, required String content}) async {
  await client.from('messages').insert({
    'conversation_id': conversationId,
    'sender_id': client.auth.currentUser!.id,
    'message_type': 'text',
    'content': content,
  });
}

/// Uploads a local media file (image/audio/video) to the **private**
/// `message-media` bucket and returns its storage PATH — not a public URL.
/// Unlike story media, message attachments are private (DM/event-room
/// content), so `messages.media_url` stores a path that's resolved to a
/// short-lived signed URL at render time via `getSignedMessageMediaUrl()`,
/// rather than a permanent public link anyone could access if it leaked.
Future<String> uploadMessageMedia(SupabaseClient client, File file, {required String extension}) async {
  final userId = client.auth.currentUser!.id;
  final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';

  await client.storage.from('message-media').upload(path, file);
  return path; // stored as-is in messages.media_url; resolved to a signed URL on read
}

/// Resolves a stored path (from `uploadMessageMedia`) to a time-limited
/// signed URL for display. Called by the UI each time a media message
/// renders — signed URLs expire (1 hour here), so this is NOT cached
/// long-term; a cache with a shorter TTL than the signed URL's expiry
/// would be a reasonable follow-up if this becomes a measurable cost.
Future<String> getSignedMessageMediaUrl(SupabaseClient client, String path) async {
  return client.storage.from('message-media').createSignedUrl(path, 3600);
}

/// Sends a media message (image, audio, or video). `durationSeconds` is
/// only meaningful for audio/video and is stashed in `content` as a plain
/// string (e.g. "0:12") since the schema's `messages.content` column is
/// free-form text and adding a dedicated duration column for one display
/// detail isn't worth a migration — the client parses it back out.
Future<void> sendMediaMessage(
  SupabaseClient client, {
  required String conversationId,
  required String mediaUrl,
  required String messageType, // 'image' | 'audio' | 'video'
  String? durationLabel,
}) async {
  await client.from('messages').insert({
    'conversation_id': conversationId,
    'sender_id': client.auth.currentUser!.id,
    'message_type': messageType,
    'media_url': mediaUrl,
    'content': durationLabel,
  });
}

/// Toggles a reaction: adds it if the current user hasn't reacted with this
/// emoji yet, removes it if they have. Mirrors the primary-key shape of
/// `message_reactions` (message_id, user_id, emoji) from migration 004, so
/// "toggle" is just an upsert-or-delete against that same unique key.
Future<void> toggleReaction(SupabaseClient client, {required String messageId, required String emoji}) async {
  final userId = client.auth.currentUser!.id;

  final existing = await client
      .from('message_reactions')
      .select()
      .eq('message_id', messageId)
      .eq('user_id', userId)
      .eq('emoji', emoji)
      .maybeSingle();

  if (existing != null) {
    await client.from('message_reactions').delete().eq('message_id', messageId).eq('user_id', userId).eq('emoji', emoji);
  } else {
    await client.from('message_reactions').insert({'message_id': messageId, 'user_id': userId, 'emoji': emoji});
  }
}

/// Marks a conversation as read up to now — updates the caller's own
/// `conversation_participants.last_read_at`. Called when a conversation
/// screen opens and whenever new messages arrive while it's foregrounded.
Future<void> markConversationRead(SupabaseClient client, String conversationId) async {
  final userId = client.auth.currentUser!.id;
  await client
      .from('conversation_participants')
      .update({'last_read_at': DateTime.now().toIso8601String()})
      .eq('conversation_id', conversationId)
      .eq('user_id', userId);
}

/// The other participant's last_read_at, for showing a "Seen" indicator on
/// the current user's own sent messages. Only meaningful for DMs (1:1) —
/// for group/event-room conversations with many participants, a single
/// "seen by" timestamp doesn't map cleanly to a WhatsApp-style checkmark,
/// so the read-receipt UI (conversation_screen.dart) only renders this for
/// `ConversationType.dm`, not group/event_room threads.
Future<DateTime?> getOtherParticipantLastRead(SupabaseClient client, String conversationId) async {
  final userId = client.auth.currentUser!.id;
  final row = await client
      .from('conversation_participants')
      .select('last_read_at')
      .eq('conversation_id', conversationId)
      .neq('user_id', userId)
      .order('last_read_at', ascending: false)
      .limit(1)
      .maybeSingle();

  final value = row?['last_read_at'] as String?;
  return value != null ? DateTime.parse(value) : null;
}
