// lib/features/home/presentation/chats_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/itango_theme.dart';
import '../../../core/router/app_router.dart';
import '../../chat/domain/chat_models.dart';
import '../../chat/domain/story_models.dart';

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = ref.watch(activeStoriesProvider);
    final highlights = ref.watch(storyHighlightsProvider);
    final eventRooms = ref.watch(eventRoomsProvider);
    final directChats = ref.watch(directConversationsProvider);

    return Scaffold(
      backgroundColor: ItangoColors.bgBase,
      appBar: AppBar(
        title: const Text('Chats'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: ItangoSpacing.s4), child: Icon(Icons.search_rounded)),
        ],
      ),
      body: RefreshIndicator(
        color: ItangoColors.brandPrimary,
        onRefresh: () async {
          ref.invalidate(activeStoriesProvider);
          ref.invalidate(eventRoomsProvider);
          ref.invalidate(directConversationsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: ItangoSpacing.s10),
          children: [
            _StoriesRow(stories: stories),
            const SizedBox(height: ItangoSpacing.s4),
            _HighlightsRow(highlights: highlights),
            const SizedBox(height: ItangoSpacing.s2),
            _SectionHeader(title: 'Event Rooms'),
            eventRooms.when(
              loading: () => const Padding(padding: EdgeInsets.all(ItangoSpacing.s4), child: LinearProgressIndicator(color: ItangoColors.brandPrimary)),
              error: (_, __) => const Padding(padding: EdgeInsets.all(ItangoSpacing.s4), child: Text('Could not load event rooms', style: TextStyle(color: ItangoColors.textSecondary))),
              data: (rooms) => rooms.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(ItangoSpacing.s4),
                      child: Text(
                        "No event rooms yet — check in at an event to unlock its chat.",
                        style: TextStyle(color: ItangoColors.textSecondary),
                      ),
                    )
                  : Column(children: rooms.map((r) => _ConversationTile(conversation: r)).toList()),
            ),
            const SizedBox(height: ItangoSpacing.s2),
            _SectionHeader(title: 'Direct Messages'),
            directChats.when(
              loading: () => const Padding(padding: EdgeInsets.all(ItangoSpacing.s4), child: LinearProgressIndicator(color: ItangoColors.brandPrimary)),
              error: (_, __) => const Padding(padding: EdgeInsets.all(ItangoSpacing.s4), child: Text('Could not load messages', style: TextStyle(color: ItangoColors.textSecondary))),
              data: (chats) => chats.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(ItangoSpacing.s4),
                      child: Text(
                        "No conversations yet — say hi to someone in Discover to get started.",
                        style: TextStyle(color: ItangoColors.textSecondary),
                      ),
                    )
                  : Column(children: chats.map((c) => _ConversationTile(conversation: c)).toList()),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(ItangoSpacing.s4, ItangoSpacing.s3, ItangoSpacing.s4, ItangoSpacing.s2),
        child: Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelLarge),
      );
}

class _StoriesRow extends StatelessWidget {
  const _StoriesRow({required this.stories});
  final AsyncValue<List<StorySummary>> stories;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: stories.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (list) => ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s4),
          children: [
            _StoryAvatar(
              label: 'My Story',
              avatarUrl: null,
              ringed: false,
              isAddButton: true,
              onTap: () => context.push(AppRoutes.storyCreator),
            ),
            for (final story in list)
              _StoryAvatar(
                label: story.username,
                avatarUrl: story.avatarUrl,
                ringed: story.hasUnviewedStory,
                onTap: () => context.push(
                  AppRoutes.storyViewerPath(story.userId),
                  extra: {'username': story.username},
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar({
    required this.label,
    required this.avatarUrl,
    required this.ringed,
    required this.onTap,
    this.isAddButton = false,
  });
  final String label;
  final String? avatarUrl;
  final bool ringed;
  final VoidCallback onTap;
  final bool isAddButton;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: ItangoSpacing.s3),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ringed ? ItangoGradients.primaryCta : null,
                border: ringed ? null : Border.all(color: ItangoColors.borderDefault, width: 1.5),
              ),
              child: CircleAvatar(
                backgroundColor: ItangoColors.bgSurfaceElevated,
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                child: isAddButton
                    ? const Icon(Icons.add, color: ItangoColors.textPrimary)
                    : (avatarUrl == null ? const Icon(Icons.person, color: ItangoColors.textSecondary) : null),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 60,
              child: Text(label, style: const TextStyle(fontSize: 11, color: ItangoColors.textSecondary), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightsRow extends StatelessWidget {
  const _HighlightsRow({required this.highlights});
  final AsyncValue<List<HighlightCollection>> highlights;

  @override
  Widget build(BuildContext context) {
    return highlights.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) => list.isEmpty
          ? const SizedBox.shrink()
          : SizedBox(
              height: 80,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s4),
                children: [
                  for (final h in list)
                    Padding(
                      padding: const EdgeInsets.only(right: ItangoSpacing.s3),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: ItangoColors.bgSurfaceElevated,
                            backgroundImage: h.coverUrl != null ? NetworkImage(h.coverUrl!) : null,
                          ),
                          const SizedBox(height: 4),
                          Text(h.name, style: const TextStyle(fontSize: 11, color: ItangoColors.textSecondary)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation});
  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => context.push(
        AppRoutes.conversationPath(conversation.conversationId),
        extra: {'title': conversation.title, 'isDm': conversation.type == ConversationType.dm},
      ),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: ItangoColors.bgSurfaceElevated,
            backgroundImage: conversation.eventCoverUrl != null ? NetworkImage(conversation.eventCoverUrl!) : null,
            child: conversation.eventCoverUrl == null
                ? Icon(conversation.type == ConversationType.eventRoom ? Icons.celebration_rounded : Icons.chat_bubble_rounded, color: ItangoColors.textSecondary, size: 20)
                : null,
          ),
          if (conversation.type == ConversationType.eventRoom)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: ItangoColors.statusLive, shape: BoxShape.circle, border: Border.all(color: ItangoColors.bgBase, width: 2)),
              ),
            ),
        ],
      ),
      title: Text(conversation.title, style: const TextStyle(color: ItangoColors.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: Text(
        conversation.lastMessagePreview ?? 'No messages yet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: ItangoColors.textSecondary, fontSize: 13),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (conversation.lastMessageAt != null)
            Text(DateFormat.jm().format(conversation.lastMessageAt!), style: const TextStyle(color: ItangoColors.textTertiary, fontSize: 11)),
          if (conversation.type == ConversationType.eventRoom) ...[
            const SizedBox(height: 4),
            _TemperatureTag(temperature: conversation.temperature),
          ],
        ],
      ),
    );
  }
}

class _TemperatureTag extends StatelessWidget {
  const _TemperatureTag({required this.temperature});
  final RoomTemperature temperature;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (temperature) {
      RoomTemperature.onFire => ('🔥 On Fire', ItangoColors.statusWarmthHot),
      RoomTemperature.hot => ('Heated', ItangoColors.statusWarmthWarm),
      RoomTemperature.warm => ('Warm', ItangoColors.accentAmber),
      RoomTemperature.cold => ('Quiet', ItangoColors.textTertiary),
    };
    return Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600));
  }
}
