// lib/features/notifications/domain/push_notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io' show Platform;

import '../../../core/supabase/supabase_providers.dart';

/// Wraps Firebase Messaging registration so it's called from exactly one
/// place (after successful login — see main.dart / auth flow) rather than
/// scattered across screens. Registration failures are swallowed rather
/// than surfaced to the user: push notifications are an enhancement, and a
/// failure to register a token should never block someone from using the app.
class PushNotificationService {
  PushNotificationService(this._client);
  final SupabaseClient _client;

  Future<void> initialize() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);

      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) await _registerToken(token);

      messaging.onTokenRefresh.listen(_registerToken);
    } catch (e) {
      // Non-fatal by design — see class docstring.
    }
  }

  Future<void> _registerToken(String token) async {
    if (_client.auth.currentUser == null) return;

    try {
      await _client.functions.invoke('register-device-token', body: {
        'fcm_token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (e) {
      // Logged via whatever crash/analytics tool is wired in Phase 14 —
      // not rethrown, per the class-level rationale above.
    }
  }
}

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref.watch(supabaseClientProvider));
});
