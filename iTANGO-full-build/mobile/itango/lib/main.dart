// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/router/app_router.dart';
import 'core/theme/itango_theme.dart';
import 'core/supabase/supabase_providers.dart';
import 'features/notifications/domain/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp();

  // Sentry wraps the whole app (runApp call happens inside appRunner) so
  // it captures uncaught errors from anywhere in the widget tree, not just
  // errors inside try/catch blocks that happen to call it explicitly.
  await SentryFlutter.init(
    (options) {
      options.dsn = dotenv.env['SENTRY_DSN'] ?? '';
      options.environment = dotenv.env['ENVIRONMENT'] ?? 'development';
      // Same sampling rationale as the web config (sentry.client.config.ts):
      // full visibility in staging, lighter sampling once there's real
      // production traffic volume to reason about cost against.
      options.tracesSampleRate = (dotenv.env['ENVIRONMENT'] == 'production') ? 0.1 : 1.0;
      // No session replay/screenshots — same rationale as web: this app
      // renders other users' photos and messages on screen, and a replay
      // recording could capture that content without their knowledge.
    },
    appRunner: () => _runApp(),
  );
}

Future<void> _runApp() async {
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    // Realtime is used for messaging (event rooms, DMs) and live attendee counts.
    realtimeClientOptions: const RealtimeClientOptions(
      eventsPerSecond: 10,
    ),
  );

  final container = ProviderContainer();

  // Register the FCM token immediately if already signed in (app relaunch);
  // for a fresh sign-in, the auth-state listener below picks it up.
  if (Supabase.instance.client.auth.currentUser != null) {
    await container.read(pushNotificationServiceProvider).initialize();
  }
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.signedIn) {
      container.read(pushNotificationServiceProvider).initialize();
    }
  });

  runApp(UncontrolledProviderScope(container: container, child: const ItangoApp()));
}

class ItangoApp extends ConsumerWidget {
  const ItangoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'iTANGO',
      debugShowCheckedModeBanner: false,
      theme: ItangoTheme.light,
      darkTheme: ItangoTheme.dark,
      themeMode: ThemeMode.dark, // dark-first, matches the confirmed brand experience
      routerConfig: router,
    );
  }
}
