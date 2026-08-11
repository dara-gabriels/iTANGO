// lib/features/chat/presentation/conversation_screen.dart
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';

import '../../../core/theme/itango_theme.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/chat_models.dart';

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.messageType,
    required this.mediaUrl,
    required this.createdAt,
    required this.reactions,
  });

  final String id;
  final String senderId;
  final String? content;
  final String messageType;
  final String? mediaUrl;
  final DateTime createdAt;
  final Map<String, int> reactions;

  factory ChatMessage.fromRow(Map<String, dynamic> row) {
    final reactionRows = (row['message_reactions'] as List?) ?? [];
    final reactionCounts = <String, int>{};
    for (final r in reactionRows) {
      final emoji = r['emoji'] as String;
      reactionCounts[emoji] = (reactionCounts[emoji] ?? 0) + 1;
    }

    return ChatMessage(
      id: row['id'] as String,
      senderId: row['sender_id'] as String? ?? '',
      content: row['content'] as String?,
      messageType: row['message_type'] as String? ?? 'text',
      mediaUrl: row['media_url'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      reactions: reactionCounts,
    );
  }
}

/// Streams messages for a conversation in real time.
///
/// NOTE: Supabase's realtime `.stream()` does not support embedded joins,
/// so reactions added by ANOTHER participant won't appear live here — only
/// this client's own optimistic toggle updates immediately. A reaction
/// added elsewhere shows up on the next full reload.
final conversationMessagesProvider =
    StreamProvider.autoDispose.family<List<ChatMessage>, String>((ref, conversationId) {
  final client = ref.watch(supabaseClientProvider);

  return client
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('conversation_id', conversationId)
      .order('created_at')
      .map((rows) => rows.map((r) => ChatMessage.fromRow(r)).toList());
});

/// Resolves a stored media path to a short-lived signed URL for display.
final signedMediaUrlProvider = FutureProvider.autoDispose.family<String, String>((ref, path) async {
  final client = ref.watch(supabaseClientProvider);
  return getSignedMessageMediaUrl(client, path);
});

/// The other participant's last-read timestamp, for a DM "Seen" indicator.
final otherParticipantLastReadProvider = FutureProvider.autoDispose.family<DateTime?, String>((ref, conversationId) async {
  final client = ref.watch(supabaseClientProvider);
  return getOtherParticipantLastRead(client, conversationId);
});

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.conversationId, this.title = 'Chat', this.isDm = true});
  final String conversationId;
  final String title;
  final bool isDm;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> with WidgetsBindingObserver {
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();
  bool _sending = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _markRead();
    _composerController.addListener(() => setState(() {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _markRead();
  }

  void _markRead() {
    markConversationRead(ref.read(supabaseClientProvider), widget.conversationId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composerController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final client = ref.read(supabaseClientProvider);
    try {
      await sendMessage(client, conversationId: widget.conversationId, content: text);
      _composerController.clear();
    } catch (_) {
      _showSendError();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() => _sending = true);
    final client = ref.read(supabaseClientProvider);
    try {
      final path = await uploadMessageMedia(client, File(picked.path), extension: 'jpg');
      await sendMediaMessage(client, conversationId: widget.conversationId, mediaUrl: path, messageType: 'image');
    } catch (_) {
      _showSendError();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    final dir = Directory.systemTemp;
    final path = '${dir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecordingAndSend() async {
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    if (path == null) return;

    setState(() => _sending = true);
    final client = ref.read(supabaseClientProvider);
    try {
      final storagePath = await uploadMessageMedia(client, File(path), extension: 'm4a');
      await sendMediaMessage(client, conversationId: widget.conversationId, mediaUrl: storagePath, messageType: 'audio');
    } catch (_) {
      _showSendError();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showSendError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't send — you may need to check in again."), backgroundColor: ItangoColors.statusDanger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(conversationMessagesProvider(widget.conversationId));
    final currentUserId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    final otherLastReadAsync = widget.isDm ? ref.watch(otherParticipantLastReadProvider(widget.conversationId)) : null;

    ref.listen(conversationMessagesProvider(widget.conversationId), (_, __) => _markRead());

    return Scaffold(
      backgroundColor: ItangoColors.bgBase,
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: ItangoColors.brandPrimary)),
              error: (err, _) => const Center(child: Text("Couldn't load messages.", style: TextStyle(color: ItangoColors.textSecondary))),
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(ItangoSpacing.s6),
                      child: Text('No messages yet — say something!', style: TextStyle(color: ItangoColors.textSecondary)),
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });

                final lastMineIndex = widget.isDm ? messages.lastIndexWhere((m) => m.senderId == currentUserId) : -1;

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(ItangoSpacing.s4),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final message = messages[i];
                    final isMine = message.senderId == currentUserId;
                    final showSeen = widget.isDm && i == lastMineIndex && isMine;

                    return _MessageBubble(
                      message: message,
                      isMine: isMine,
                      showSeenIndicator: showSeen,
                      otherLastRead: showSeen ? otherLastReadAsync?.valueOrNull : null,
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(ItangoSpacing.s3),
              child: _isRecording
                  ? _RecordingBar(
                      onStop: _stopRecordingAndSend,
                      onCancel: () async {
                        await _recorder.cancel();
                        setState(() => _isRecording = false);
                      },
                    )
                  : Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.image_outlined, color: ItangoColors.textSecondary),
                          onPressed: _sending ? null : _sendImage,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _composerController,
                            style: const TextStyle(color: ItangoColors.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Message...',
                              contentPadding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s4, vertical: ItangoSpacing.s3),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(ItangoRadius.pill), borderSide: BorderSide.none),
                              filled: true,
                              fillColor: ItangoColors.bgSurfaceElevated,
                            ),
                            onSubmitted: (_) => _sendText(),
                          ),
                        ),
                        const SizedBox(width: ItangoSpacing.s2),
                        GestureDetector(
                          onTap: _composerController.text.trim().isEmpty ? _startRecording : _sendText,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(gradient: ItangoGradients.primaryCta, shape: BoxShape.circle),
                            child: _sending
                                ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Icon(_composerController.text.trim().isEmpty ? Icons.mic_rounded : Icons.send_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingBar extends StatelessWidget {
  const _RecordingBar({required this.onStop, required this.onCancel});
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(icon: const Icon(Icons.delete_outline, color: ItangoColors.statusDanger), onPressed: onCancel),
        const Expanded(
          child: Row(
            children: [
              Icon(Icons.fiber_manual_record, color: ItangoColors.statusLive, size: 14),
              SizedBox(width: ItangoSpacing.s2),
              Text('Recording voice note...', style: TextStyle(color: ItangoColors.textPrimary)),
            ],
          ),
        ),
        GestureDetector(
          onTap: onStop,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(gradient: ItangoGradients.primaryCta, shape: BoxShape.circle),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showSeenIndicator,
    required this.otherLastRead,
  });

  final ChatMessage message;
  final bool isMine;
  final bool showSeenIndicator;
  final DateTime? otherLastRead;

  static const _quickReactions = ['❤️', '🔥', '😂', '👍', '😮'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSystem = message.senderId.isEmpty;

    if (isSystem) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: ItangoSpacing.s2),
        padding: const EdgeInsets.all(ItangoSpacing.s3),
        decoration: BoxDecoration(color: ItangoColors.statusSuccess.withOpacity(0.12), borderRadius: BorderRadius.circular(ItangoRadius.md)),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: ItangoColors.statusSuccess, size: 18),
            const SizedBox(width: ItangoSpacing.s2),
            Expanded(child: Text(message.content ?? '', style: const TextStyle(color: ItangoColors.statusSuccess, fontWeight: FontWeight.w600, fontSize: 13))),
          ],
        ),
      );
    }

    return GestureDetector(
      onLongPress: () => _showReactionPicker(context, ref),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
              decoration: BoxDecoration(
                gradient: message.messageType == 'text' && isMine ? ItangoGradients.primaryCta : null,
                color: message.messageType == 'text' && !isMine ? ItangoColors.bgSurfaceElevated : null,
                borderRadius: BorderRadius.circular(ItangoRadius.lg),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildContent(context, ref, isMine),
            ),
            if (message.reactions.isNotEmpty)
              _ReactionRow(
                reactions: message.reactions,
                onTap: (emoji) => toggleReaction(ref.read(supabaseClientProvider), messageId: message.id, emoji: emoji),
              ),
            if (showSeenIndicator)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Text(
                  (otherLastRead != null && otherLastRead!.isAfter(message.createdAt)) ? 'Seen' : 'Delivered',
                  style: const TextStyle(color: ItangoColors.textTertiary, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, bool isMine) {
    switch (message.messageType) {
      case 'image':
        if (message.mediaUrl == null) return const SizedBox(width: 200, height: 200);
        return Consumer(builder: (_, innerRef, __) {
          final urlAsync = innerRef.watch(signedMediaUrlProvider(message.mediaUrl!));
          return urlAsync.when(
            loading: () => const SizedBox(width: 200, height: 200, child: Center(child: CircularProgressIndicator())),
            error: (_, __) => const SizedBox(width: 200, height: 100, child: Center(child: Icon(Icons.broken_image, color: ItangoColors.textTertiary))),
            data: (url) => Image.network(url, width: 220, fit: BoxFit.cover),
          );
        });
      case 'audio':
        if (message.mediaUrl == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s4, vertical: ItangoSpacing.s3),
          child: _VoiceNotePlayer(path: message.mediaUrl!, tint: isMine ? Colors.white : ItangoColors.textPrimary),
        );
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s4, vertical: ItangoSpacing.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(message.content ?? '', style: TextStyle(color: isMine ? Colors.white : ItangoColors.textPrimary)),
              const SizedBox(height: 2),
              Text(DateFormat.jm().format(message.createdAt), style: TextStyle(color: isMine ? Colors.white70 : ItangoColors.textTertiary, fontSize: 10)),
            ],
          ),
        );
    }
  }

  void _showReactionPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ItangoColors.bgSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ItangoRadius.xl2))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(ItangoSpacing.s5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _quickReactions.map((emoji) {
            return GestureDetector(
              onTap: () {
                toggleReaction(ref.read(supabaseClientProvider), messageId: message.id, emoji: emoji);
                Navigator.pop(context);
              },
              child: Text(emoji, style: const TextStyle(fontSize: 32)),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({required this.reactions, required this.onTap});
  final Map<String, int> reactions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 4,
        children: reactions.entries.map((entry) {
          return GestureDetector(
            onTap: () => onTap(entry.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: ItangoColors.bgSurfaceElevated, borderRadius: BorderRadius.circular(ItangoRadius.pill)),
              child: Text('${entry.key} ${entry.value}', style: const TextStyle(fontSize: 12)),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Voice-note player with real playback via `audioplayers`. Each bubble
/// gets its own AudioPlayer instance, disposed with the widget. Stopping
/// other bubbles' playback when a new one starts is NOT implemented —
/// fine for a thread where voice notes are sparse, worth addressing with a
/// shared player manager if voice-note-heavy threads become common.
class _VoiceNotePlayer extends ConsumerStatefulWidget {
  const _VoiceNotePlayer({required this.path, required this.tint});
  final String path;
  final Color tint;

  @override
  ConsumerState<_VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends ConsumerState<_VoiceNotePlayer> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  Duration? _duration;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(String url) async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(url));
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final urlAsync = ref.watch(signedMediaUrlProvider(widget.path));

    return urlAsync.when(
      loading: () => SizedBox(
        width: 140,
        height: 32,
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: widget.tint))),
      ),
      error: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: widget.tint),
          const SizedBox(width: 8),
          Text('Voice note unavailable', style: TextStyle(color: widget.tint, fontSize: 13)),
        ],
      ),
      data: (url) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: widget.tint, size: 32),
            onPressed: () => _togglePlay(url),
          ),
          const SizedBox(width: 8),
          Text(
            _duration != null ? '${_formatDuration(_position)} / ${_formatDuration(_duration!)}' : 'Voice note',
            style: TextStyle(color: widget.tint, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
