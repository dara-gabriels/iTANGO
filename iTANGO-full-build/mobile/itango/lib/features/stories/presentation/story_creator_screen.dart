// lib/features/stories/presentation/story_creator_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/itango_theme.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/story_viewer_models.dart';

class StoryCreatorScreen extends ConsumerStatefulWidget {
  const StoryCreatorScreen({super.key});

  @override
  ConsumerState<StoryCreatorScreen> createState() => _StoryCreatorScreenState();
}

class _StoryCreatorScreenState extends ConsumerState<StoryCreatorScreen> {
  File? _selectedImage;
  final _captionController = TextEditingController();
  bool _isPosting = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<void> _post({String? highlightCollection}) async {
    if (_selectedImage == null) return;
    setState(() => _isPosting = true);

    final client = ref.read(supabaseClientProvider);
    try {
      final mediaUrl = await uploadStoryMedia(client, _selectedImage!, mediaType: 'image');
      await createStory(
        client,
        mediaUrl: mediaUrl,
        mediaType: 'image',
        caption: _captionController.text.trim().isEmpty ? null : _captionController.text.trim(),
        highlightCollection: highlightCollection,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(highlightCollection != null ? 'Saved to Highlights' : 'Posted to your story'),
            backgroundColor: ItangoColors.statusSuccess,
          ),
        );
        context.pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't post — try again."), backgroundColor: ItangoColors.statusDanger),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('New Story'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
      ),
      body: _selectedImage == null ? _buildPicker() : _buildPreview(),
    );
  }

  Widget _buildPicker() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_a_photo_rounded, color: Colors.white54, size: 64),
          const SizedBox(height: ItangoSpacing.s6),
          ItangoGradientButton(
            label: 'Take Photo',
            icon: Icons.camera_alt_rounded,
            onPressed: () => _pickImage(ImageSource.camera),
          ),
          const SizedBox(height: ItangoSpacing.s3),
          OutlinedButton(
            onPressed: () => _pickImage(ImageSource.gallery),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: ItangoColors.borderDefault),
              minimumSize: const Size(200, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ItangoRadius.pill)),
            ),
            child: const Text('Choose from Gallery'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(_selectedImage!, fit: BoxFit.cover),
        Positioned(
          left: ItangoSpacing.s4,
          right: ItangoSpacing.s4,
          bottom: ItangoSpacing.s6,
          child: Column(
            children: [
              TextField(
                controller: _captionController,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'Add a caption...',
                  hintStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.black38,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ItangoRadius.pill), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: ItangoSpacing.s4),
              if (_isPosting)
                const CircularProgressIndicator(color: Colors.white)
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showHighlightNameDialog(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: ItangoSpacing.s3),
                        ),
                        child: const Text('Save to Highlights'),
                      ),
                    ),
                    const SizedBox(width: ItangoSpacing.s3),
                    Expanded(
                      child: ItangoGradientButton(label: 'Add to Story', onPressed: () => _post()),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showHighlightNameDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ItangoColors.bgSurface,
        title: const Text('Highlight name', style: TextStyle(color: ItangoColors.textPrimary)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: ItangoColors.textPrimary),
          decoration: const InputDecoration(hintText: 'e.g. Neon Nights'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save', style: TextStyle(color: ItangoColors.brandPrimary)),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await _post(highlightCollection: name);
    }
  }
}
