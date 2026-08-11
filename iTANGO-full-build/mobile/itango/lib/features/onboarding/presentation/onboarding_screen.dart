// lib/features/onboarding/presentation/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/itango_theme.dart';
import '../../../core/router/app_router.dart';
import '../../discover/domain/discover_person.dart';
import '../domain/onboarding_controller.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _step = 0;
  static const _totalSteps = 4;

  void _next() {
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
      _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _finish() async {
    final success = await ref.read(onboardingControllerProvider.notifier).complete();
    if (success && mounted) {
      context.go(AppRoutes.home);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ItangoColors.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(ItangoSpacing.s5),
              child: Row(
                children: List.generate(_totalSteps, (i) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: i <= _step ? ItangoGradients.primaryCta : null,
                        color: i <= _step ? null : ItangoColors.borderSubtle,
                        borderRadius: BorderRadius.circular(ItangoRadius.pill),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _LocationPermissionStep(onNext: _next),
                  _NotificationPermissionStep(onNext: _next),
                  _VibeTagStep(onNext: _next),
                  _ProfileSetupStep(onFinish: _finish),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.icon, required this.title, required this.description, required this.child});
  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(ItangoSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ItangoColors.brandPrimary, size: 48),
          const SizedBox(height: ItangoSpacing.s5),
          Text(title, style: const TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 26, fontWeight: FontWeight.w700, color: ItangoColors.textPrimary)),
          const SizedBox(height: ItangoSpacing.s2),
          Text(description, style: const TextStyle(color: ItangoColors.textSecondary, height: 1.4)),
          const SizedBox(height: ItangoSpacing.s6),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _LocationPermissionStep extends ConsumerWidget {
  const _LocationPermissionStep({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StepScaffold(
      icon: Icons.location_on_rounded,
      title: 'Find what\'s near you',
      description: 'iTANGO shows you live events and people nearby. We only use your location while the app is open.',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ItangoGradientButton(
            label: 'Enable Location',
            onPressed: () async {
              await ref.read(onboardingControllerProvider.notifier).requestLocationPermission();
              onNext();
            },
          ),
          const SizedBox(height: ItangoSpacing.s3),
          TextButton(onPressed: onNext, child: const Text('Skip for now', style: TextStyle(color: ItangoColors.textSecondary))),
        ],
      ),
    );
  }
}

class _NotificationPermissionStep extends ConsumerWidget {
  const _NotificationPermissionStep({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StepScaffold(
      icon: Icons.notifications_active_rounded,
      title: 'Never miss the vibe',
      description: 'Get notified when your event room heats up, someone says hi, or your ticket is confirmed.',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ItangoGradientButton(
            label: 'Enable Notifications',
            onPressed: () async {
              await ref.read(onboardingControllerProvider.notifier).requestNotificationPermission();
              onNext();
            },
          ),
          const SizedBox(height: ItangoSpacing.s3),
          TextButton(onPressed: onNext, child: const Text('Skip for now', style: TextStyle(color: ItangoColors.textSecondary))),
        ],
      ),
    );
  }
}

class _VibeTagStep extends ConsumerWidget {
  const _VibeTagStep({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(onboardingControllerProvider).selectedVibeTags;

    return _StepScaffold(
      icon: Icons.local_fire_department_rounded,
      title: "What's your vibe?",
      description: 'Pick as many as fit — this helps people find you on Discover. You can change these anytime.',
      child: Column(
        children: [
          Expanded(
            child: Wrap(
              spacing: ItangoSpacing.s2,
              runSpacing: ItangoSpacing.s2,
              children: VibeTag.values.map((tag) {
                final isSelected = selected.contains(tag);
                return GestureDetector(
                  onTap: () => ref.read(onboardingControllerProvider.notifier).toggleVibeTag(tag),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s4, vertical: ItangoSpacing.s3),
                    decoration: BoxDecoration(
                      gradient: isSelected ? ItangoGradients.primaryCta : null,
                      color: isSelected ? null : ItangoColors.bgSurfaceElevated,
                      borderRadius: BorderRadius.circular(ItangoRadius.pill),
                    ),
                    child: Text('${tag.emoji} ${tag.label}', style: TextStyle(color: isSelected ? Colors.white : ItangoColors.textSecondary, fontWeight: FontWeight.w600)),
                  ),
                );
              }).toList(),
            ),
          ),
          ItangoGradientButton(label: 'Continue', onPressed: onNext),
        ],
      ),
    );
  }
}

class _ProfileSetupStep extends ConsumerStatefulWidget {
  const _ProfileSetupStep({required this.onFinish});
  final VoidCallback onFinish;

  @override
  ConsumerState<_ProfileSetupStep> createState() => _ProfileSetupStepState();
}

class _ProfileSetupStepState extends ConsumerState<_ProfileSetupStep> {
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    ref.read(onboardingControllerProvider.notifier)
      ..setDisplayName(_displayNameController.text.trim())
      ..setUsername(_usernameController.text.trim());

    await Future.delayed(Duration.zero); // let state updates land before complete() reads them
    final success = await ref.read(onboardingControllerProvider.notifier).complete();
    if (success) widget.onFinish();
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(onboardingControllerProvider).usernameError;

    return _StepScaffold(
      icon: Icons.person_rounded,
      title: 'Create your profile',
      description: 'This is how people will find and recognize you on iTANGO.',
      child: Column(
        children: [
          TextField(
            controller: _displayNameController,
            style: const TextStyle(color: ItangoColors.textPrimary),
            decoration: const InputDecoration(hintText: 'Display name, e.g. Sarah Johnson'),
          ),
          const SizedBox(height: ItangoSpacing.s3),
          TextField(
            controller: _usernameController,
            style: const TextStyle(color: ItangoColors.textPrimary),
            decoration: InputDecoration(hintText: 'Username, e.g. sarahjay', errorText: error, prefixText: '@'),
          ),
          const Spacer(),
          _submitting
              ? const CircularProgressIndicator(color: ItangoColors.brandPrimary)
              : ItangoGradientButton(label: 'Enter iTANGO', onPressed: _submit),
        ],
      ),
    );
  }
}
