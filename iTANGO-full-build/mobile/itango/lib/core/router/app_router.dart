// lib/core/router/app_router.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../supabase/supabase_providers.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/otp_verify_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/home/presentation/app_shell.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/home/presentation/discover_screen.dart';
import '../../features/home/presentation/chats_screen.dart';
import '../../features/home/presentation/profile_screen.dart';
import '../../features/events/presentation/event_detail_screen.dart';
import '../../features/events/presentation/check_in_screen.dart';
import '../../features/chat/presentation/conversation_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/stories/presentation/story_viewer_screen.dart';
import '../../features/stories/presentation/story_creator_screen.dart';

/// Route paths as constants — avoids magic strings scattered across the app
/// and makes renaming a route a one-line change.
abstract class AppRoutes {
  static const login = '/login';
  static const otpVerify = '/login/verify';
  static const onboarding = '/onboarding';
  static const home = '/home';
  static const discover = '/discover';
  static const chats = '/chats';
  static const profile = '/profile';
  static const eventDetail = '/events/:eventId';
  static const eventCheckIn = '/events/:eventId/checkin';
  static const conversation = '/chats/:conversationId';
  static const notifications = '/notifications';
  static const storyViewer = '/stories/:userId';
  static const storyCreator = '/stories/create';

  static String storyViewerPath(String userId) => '/stories/$userId';

  static String eventDetailPath(String eventId) => '/events/$eventId';
  static String eventCheckInPath(String eventId) => '/events/$eventId/checkin';
  static String conversationPath(String conversationId) => '/chats/$conversationId';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // Rebuild the router's redirect decisions whenever auth state changes —
  // GoRouter's `refreshListenable` needs a Listenable, so we bridge the
  // Riverpod stream via a small adapter rather than polling.
  final authNotifier = ref.watch(_goRouterRefreshProvider);

  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: authNotifier,
    redirect: (context, state) async {
      final user = ref.read(currentUserProvider);
      final isLoggedIn = user != null;
      final isAuthRoute = state.matchedLocation.startsWith('/login');
      final isOnboardingRoute = state.matchedLocation == AppRoutes.onboarding;

      if (!isLoggedIn && !isAuthRoute) return AppRoutes.login;
      if (!isLoggedIn) return null;

      if (isAuthRoute) {
        // Just logged in — decide between onboarding and home. This is an
        // async DB read on every redirect evaluation, which is a real cost;
        // acceptable at MVP traffic, but worth promoting to a cached
        // Riverpod provider (invalidated only on logout/onboarding-complete)
        // if this router runs hot enough to show up in profiling later.
        final completed = await _hasCompletedOnboarding(ref);
        return completed ? AppRoutes.home : AppRoutes.onboarding;
      }

      if (!isOnboardingRoute) {
        final completed = await _hasCompletedOnboarding(ref);
        if (!completed) return AppRoutes.onboarding;
      }

      return null; // no redirect needed
    },
    routes: [
      GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(path: AppRoutes.otpVerify, builder: (_, state) {
        final phone = state.extra as String? ?? '';
        return OtpVerifyScreen(phoneNumber: phone);
      }),
      GoRoute(path: AppRoutes.onboarding, builder: (_, __) => const OnboardingScreen()),

      // Shell route: bottom nav persists across these 5 tabs, matching the
      // confirmed structure (Home / Discover / Create-FAB / Chats / Profile).
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: AppRoutes.home, builder: (_, __) => const HomeScreen()),
          GoRoute(path: AppRoutes.discover, builder: (_, __) => const DiscoverScreen()),
          GoRoute(path: AppRoutes.chats, builder: (_, __) => const ChatsScreen()),
          GoRoute(path: AppRoutes.profile, builder: (_, __) => const ProfileScreen()),
        ],
      ),

      // Pushed full-screen (outside the shell) — these are focused, single-
      // task flows where the bottom nav would just be a distraction: buying
      // a ticket, verifying presence, and reading a conversation thread.
      GoRoute(
        path: AppRoutes.eventDetail,
        builder: (_, state) => EventDetailScreen(eventId: state.pathParameters['eventId']!),
      ),
      GoRoute(
        path: AppRoutes.eventCheckIn,
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CheckInScreen(
            eventId: state.pathParameters['eventId']!,
            eventTitle: extra?['eventTitle'] as String? ?? 'this event',
          );
        },
      ),
      GoRoute(
        path: AppRoutes.conversation,
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ConversationScreen(
            conversationId: state.pathParameters['conversationId']!,
            title: extra?['title'] as String? ?? 'Chat',
            isDm: extra?['isDm'] as bool? ?? true,
          );
        },
      ),
      GoRoute(path: AppRoutes.notifications, builder: (_, __) => const NotificationsScreen()),
      GoRoute(
        path: AppRoutes.storyViewer,
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return StoryViewerScreen(
            userId: state.pathParameters['userId']!,
            username: extra?['username'] as String? ?? '',
          );
        },
      ),
      GoRoute(path: AppRoutes.storyCreator, builder: (_, __) => const StoryCreatorScreen()),
    ],
  );
});

/// Bridges Riverpod's authStateProvider (a Stream) into a Listenable, which
/// is what GoRouter's `refreshListenable` expects. Without this, the router
/// would only re-evaluate `redirect` on navigation, not on sign-in/sign-out.
final _goRouterRefreshProvider = Provider<_GoRouterRefreshNotifier>((ref) {
  final notifier = _GoRouterRefreshNotifier();
  ref.listen(authStateProvider, (_, __) => notifier.notify());
  return notifier;
});

class _GoRouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

Future<bool> _hasCompletedOnboarding(Ref ref) async {
  final client = ref.read(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) return false;

  final row = await client.from('profiles').select('onboarding_completed').eq('id', userId).maybeSingle();
  return row?['onboarding_completed'] as bool? ?? false;
}
