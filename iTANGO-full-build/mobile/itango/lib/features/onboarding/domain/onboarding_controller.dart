// lib/features/onboarding/domain/onboarding_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../discover/domain/discover_person.dart';

class OnboardingData {
  const OnboardingData({
    this.displayName = '',
    this.username = '',
    this.selectedVibeTags = const {},
    this.locationGranted = false,
    this.notificationsGranted = false,
    this.usernameError,
  });

  final String displayName;
  final String username;
  final Set<VibeTag> selectedVibeTags;
  final bool locationGranted;
  final bool notificationsGranted;
  final String? usernameError;

  OnboardingData copyWith({
    String? displayName,
    String? username,
    Set<VibeTag>? selectedVibeTags,
    bool? locationGranted,
    bool? notificationsGranted,
    String? usernameError,
  }) {
    return OnboardingData(
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      selectedVibeTags: selectedVibeTags ?? this.selectedVibeTags,
      locationGranted: locationGranted ?? this.locationGranted,
      notificationsGranted: notificationsGranted ?? this.notificationsGranted,
      usernameError: usernameError,
    );
  }
}

class OnboardingController extends StateNotifier<OnboardingData> {
  OnboardingController(this._ref) : super(const OnboardingData());
  final Ref _ref;

  void setDisplayName(String value) => state = state.copyWith(displayName: value);

  void setUsername(String value) => state = state.copyWith(username: value.toLowerCase(), usernameError: null);

  void toggleVibeTag(VibeTag tag) {
    final updated = Set<VibeTag>.from(state.selectedVibeTags);
    updated.contains(tag) ? updated.remove(tag) : updated.add(tag);
    state = state.copyWith(selectedVibeTags: updated);
  }

  Future<void> requestLocationPermission() async {
    final status = await Permission.locationWhenInUse.request();
    state = state.copyWith(locationGranted: status.isGranted);
  }

  Future<void> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    state = state.copyWith(notificationsGranted: status.isGranted);
  }

  /// Validates the username against the same pattern enforced by the DB
  /// CHECK constraint (migration 001: `^[a-z0-9_]{3,20}$`) so the user gets
  /// immediate feedback instead of a raw Postgres constraint-violation
  /// message after submitting.
  bool _isValidUsername(String username) => RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(username);

  Future<bool> complete() async {
    if (!_isValidUsername(state.username)) {
      state = state.copyWith(usernameError: '3-20 characters: lowercase letters, numbers, underscore only');
      return false;
    }

    final client = _ref.read(supabaseClientProvider);
    final userId = client.auth.currentUser!.id;

    try {
      await client.from('profiles').update({
        'username': state.username,
        'display_name': state.displayName.isEmpty ? state.username : state.displayName,
        'onboarding_completed': true,
      }).eq('id', userId);

      if (state.selectedVibeTags.isNotEmpty) {
        await client.from('user_vibe_tags').insert(
          state.selectedVibeTags.map((tag) => {'user_id': userId, 'tag': tag.dbValue}).toList(),
        );
      }

      // Best-effort — an initial location snapshot improves early Discover
      // results, but onboarding shouldn't hard-fail if this errors.
      if (state.locationGranted) {
        try {
          final position = await Geolocator.getCurrentPosition();
          await client.from('profiles').update({
            'current_location': 'SRID=4326;POINT(${position.longitude} ${position.latitude})',
          }).eq('id', userId);
        } catch (_) {/* non-fatal */}
      }

      return true;
    } on Object catch (e) {
      final message = e.toString();
      if (message.contains('username_format') || message.contains('duplicate key')) {
        state = state.copyWith(usernameError: 'That username is taken or invalid — try another.');
      }
      return false;
    }
  }
}

final onboardingControllerProvider = StateNotifierProvider.autoDispose<OnboardingController, OnboardingData>((ref) {
  return OnboardingController(ref);
});
