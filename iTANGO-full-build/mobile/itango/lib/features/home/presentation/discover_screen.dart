// lib/features/home/presentation/discover_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/itango_theme.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../discover/domain/discover_person.dart';
import '../../chat/domain/chat_models.dart';

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(discoverPeopleProvider);
    final selectedTag = ref.watch(selectedVibeTagProvider);

    return Scaffold(
      backgroundColor: ItangoColors.bgBase,
      appBar: AppBar(title: const Text('Discover People')),
      body: RefreshIndicator(
        color: ItangoColors.brandPrimary,
        onRefresh: () async => ref.invalidate(discoverPeopleProvider),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s4, vertical: ItangoSpacing.s3),
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _VibeChip(
                      label: 'All',
                      selected: selectedTag == null,
                      onTap: () => ref.read(selectedVibeTagProvider.notifier).state = null,
                    ),
                    const SizedBox(width: ItangoSpacing.s2),
                    for (final tag in VibeTag.values) ...[
                      _VibeChip(
                        label: '${tag.emoji} ${tag.label}',
                        selected: selectedTag == tag,
                        onTap: () => ref.read(selectedVibeTagProvider.notifier).state = tag,
                      ),
                      const SizedBox(width: ItangoSpacing.s2),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: people.when(
                loading: () => const Center(child: CircularProgressIndicator(color: ItangoColors.brandPrimary)),
                error: (err, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(ItangoSpacing.s6),
                    child: Text(
                      "Couldn't load people nearby. Pull to refresh.",
                      style: const TextStyle(color: ItangoColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                data: (list) => list.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(ItangoSpacing.s6),
                          child: Text(
                            "No one nearby matches this vibe right now — try 'All' or check back later.",
                            style: TextStyle(color: ItangoColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(ItangoSpacing.s4),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: ItangoSpacing.s3,
                          crossAxisSpacing: ItangoSpacing.s3,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _PersonCard(person: list[i]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VibeChip extends StatelessWidget {
  const _VibeChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s4, vertical: ItangoSpacing.s2),
        decoration: BoxDecoration(
          gradient: selected ? ItangoGradients.primaryCta : null,
          color: selected ? null : ItangoColors.bgSurfaceElevated,
          borderRadius: BorderRadius.circular(ItangoRadius.pill),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : ItangoColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _PersonCard extends ConsumerWidget {
  const _PersonCard({required this.person});
  final DiscoverPerson person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: ItangoColors.bgSurface,
        borderRadius: BorderRadius.circular(ItangoRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                person.avatarUrl != null
                    ? Image.network(person.avatarUrl!, fit: BoxFit.cover)
                    : Container(color: ItangoColors.bgSurfaceElevated),
                Positioned(
                  top: ItangoSpacing.s2,
                  right: ItangoSpacing.s2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s2, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(ItangoRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt, color: ItangoColors.accentAmber, size: 13),
                        Text(' ${person.energyScore}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(ItangoSpacing.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${person.displayName}', style: const TextStyle(color: ItangoColors.textPrimary, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${person.distanceKm.toStringAsFixed(0)}m away · ${person.mutualEventCount} mutual',
                  style: const TextStyle(color: ItangoColors.textTertiary, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: ItangoSpacing.s2),
                SizedBox(
                  width: double.infinity,
                  child: ItangoGradientButton(
                    label: 'Say Hi',
                    onPressed: () => _sayHi(context, ref, person),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sayHi(BuildContext context, WidgetRef ref, DiscoverPerson person) async {
    final client = ref.read(supabaseClientProvider);
    try {
      final conversationId = await startOrGetDmConversation(client, person.userId);
      await sendMessage(client, conversationId: conversationId, content: '👋 Hey ${person.displayName}!');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Said hi to ${person.displayName}!'), backgroundColor: ItangoColors.statusSuccess),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't send — try again."), backgroundColor: ItangoColors.statusDanger),
        );
      }
    }
  }
}
