// lib/features/home/presentation/app_shell.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/itango_theme.dart';
import '../../../core/router/app_router.dart';

/// Persistent shell around the 5 confirmed tabs. The FAB is a real 5th
/// nav-bar slot (not a floating overlay button) to match the extracted
/// screens, where it sits inline in the bottom bar between Discover and Chats.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    AppRoutes.home,
    AppRoutes.discover,
    AppRoutes.chats,
    AppRoutes.profile,
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _tabs.indexOf(location);
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: SizedBox(
        height: 64 + MediaQuery.of(context).padding.bottom,
        child: Row(
          children: [
            _NavItem(icon: Icons.home_rounded, label: 'Home', selected: currentIndex == 0,
                onTap: () => context.go(AppRoutes.home)),
            _NavItem(icon: Icons.explore_rounded, label: 'Discover', selected: currentIndex == 1,
                onTap: () => context.go(AppRoutes.discover)),
            _CreateFabNavItem(onTap: () => _openCreateSheet(context)),
            _NavItem(icon: Icons.chat_bubble_rounded, label: 'Chats', selected: currentIndex == 2,
                onTap: () => context.go(AppRoutes.chats)),
            _NavItem(icon: Icons.person_rounded, label: 'Profile', selected: currentIndex == 3,
                onTap: () => context.go(AppRoutes.profile)),
          ],
        ),
      ),
    );
  }

  void _openCreateSheet(BuildContext context) {
    // Context-aware create menu. Story creation is fully wired
    // (features/stories/); Event and Post creation from mobile are still
    // next-build-pass items — each option below is disabled with a label
    // explaining why, rather than hidden, so the gap is visible in the UI
    // itself and not just in a README.
    showModalBottomSheet(
      context: context,
      backgroundColor: ItangoColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ItangoRadius.xl2)),
      ),
      builder: (_) => const _CreateSheetPlaceholder(),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? ItangoColors.brandPrimary : ItangoColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _CreateFabNavItem extends StatelessWidget {
  const _CreateFabNavItem({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              gradient: ItangoGradients.primaryCta,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

class _CreateSheetPlaceholder extends StatelessWidget {
  const _CreateSheetPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(ItangoSpacing.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Create', style: TextStyle(color: ItangoColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: ItangoSpacing.s4),
          _CreateOptionTile(
            icon: Icons.auto_awesome_rounded,
            label: 'Story',
            onTap: () {
              Navigator.of(context).pop();
              context.push(AppRoutes.storyCreator);
            },
          ),
          const _CreateOptionTile(
            icon: Icons.celebration_rounded,
            label: 'Event (organizer web dashboard for now — mobile creation is next build pass)',
            onTap: null,
          ),
          const _CreateOptionTile(
            icon: Icons.image_rounded,
            label: 'Post (next build pass)',
            onTap: null,
          ),
        ],
      ),
    );
  }
}

class _CreateOptionTile extends StatelessWidget {
  const _CreateOptionTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: ItangoColors.brandPrimary),
        title: Text(label, style: const TextStyle(color: ItangoColors.textPrimary)),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
