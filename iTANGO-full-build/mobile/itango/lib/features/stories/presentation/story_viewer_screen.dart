// lib/features/stories/presentation/story_viewer_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/itango_theme.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../chat/domain/chat_models.dart';
import '../domain/story_viewer_models.dart';

class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({super.key, required this.userId, required this.username});
  final String userId;
  final String username;

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen> with SingleTickerProviderStateMixin {
  static const _storyDuration = Duration(seconds: 5);
  late AnimationController _progressController;
  int _currentIndex = 0;
  List<StoryItem> _stories = [];

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this, duration: _storyDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _advance();
      });
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _startStoryAt(int index) {
    if (index < 0 || index >= _stories.length) {
      context.pop();
      return;
    }
    setState(() => _currentIndex = index);
    markStoryViewed(ref.read(supabaseClientProvider), _stories[index].id);
    _progressController
      ..reset()
      ..forward();
  }

  void _advance() => _startStoryAt(_currentIndex + 1);
  void _goBack() => _startStoryAt(_currentIndex - 1);

  Future<void> _sendReply(String text) async {
    // Story replies land as a DM to the story's author — reuses the same
    // startOrGetDmConversation/sendMessage helpers as Discover's "Say Hi"
    // and Profile's "Message" action, so all three entry points converge
    // on one conversation thread rather than creating parallel DMs.
    _progressController.stop(); // pause the story while the reply sends, resumed after
    final client = ref.read(supabaseClientProvider);

    try {
      final conversationId = await startOrGetDmConversation(client, widget.userId);
      await sendMessage(client, conversationId: conversationId, content: 'Replying to your story: $text');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reply sent'), backgroundColor: ItangoColors.statusSuccess),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't send reply"), backgroundColor: ItangoColors.statusDanger),
        );
      }
    } finally {
      if (mounted) _progressController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final storiesAsync = ref.watch(userStoriesProvider(widget.userId));

    return Scaffold(
      backgroundColor: Colors.black,
      body: storiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
        error: (_, __) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Could not load this story.', style: TextStyle(color: Colors.white)),
              TextButton(onPressed: () => context.pop(), child: const Text('Close', style: TextStyle(color: Colors.white70))),
            ],
          ),
        ),
        data: (stories) {
          if (stories.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No active stories.', style: TextStyle(color: Colors.white)),
                  TextButton(onPressed: () => context.pop(), child: const Text('Close', style: TextStyle(color: Colors.white70))),
                ],
              ),
            );
          }

          if (_stories.isEmpty) {
            _stories = stories;
            WidgetsBinding.instance.addPostFrameCallback((_) => _startStoryAt(0));
          }

          if (_currentIndex >= _stories.length) return const SizedBox.shrink();
          final story = _stories[_currentIndex];

          return GestureDetector(
            onTapUp: (details) {
              final screenWidth = MediaQuery.of(context).size.width;
              details.localPosition.dx < screenWidth / 3 ? _goBack() : _advance();
            },
            onLongPress: () => _progressController.stop(),
            onLongPressUp: () => _progressController.forward(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(story.mediaUrl, fit: BoxFit.cover),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent, Colors.black54],
                      stops: [0.0, 0.3, 1.0],
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s3, vertical: ItangoSpacing.s2),
                    child: Column(
                      children: [
                        Row(
                          children: _stories.asMap().entries.map((entry) {
                            return Expanded(
                              child: Container(
                                height: 3,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white30,
                                  borderRadius: BorderRadius.circular(ItangoRadius.pill),
                                ),
                                child: entry.key == _currentIndex
                                    ? AnimatedBuilder(
                                        animation: _progressController,
                                        builder: (_, __) => FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: _progressController.value,
                                          child: Container(
                                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(ItangoRadius.pill)),
                                          ),
                                        ),
                                      )
                                    : entry.key < _currentIndex
                                        ? Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(ItangoRadius.pill)))
                                        : null,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: ItangoSpacing.s3),
                        Row(
                          children: [
                            Text(widget.username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            const Spacer(),
                            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => context.pop()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (story.caption != null)
                  Positioned(
                    left: ItangoSpacing.s4,
                    right: ItangoSpacing.s4,
                    bottom: ItangoSpacing.s10,
                    child: Text(story.caption!, style: const TextStyle(color: Colors.white, fontSize: 15), textAlign: TextAlign.center),
                  ),
                Positioned(
                  left: ItangoSpacing.s4,
                  right: ItangoSpacing.s4,
                  bottom: ItangoSpacing.s4,
                  child: _ReplyBar(onSend: _sendReply),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReplyBar extends StatefulWidget {
  const _ReplyBar({required this.onSend});
  final ValueChanged<String> onSend;

  @override
  State<_ReplyBar> createState() => _ReplyBarState();
}

class _ReplyBarState extends State<_ReplyBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Reply...',
        hintStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white24,
        contentPadding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s4, vertical: ItangoSpacing.s3),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ItangoRadius.pill), borderSide: BorderSide.none),
      ),
      onSubmitted: (text) {
        if (text.trim().isEmpty) return;
        widget.onSend(text.trim());
        _controller.clear();
      },
    );
  }
}
