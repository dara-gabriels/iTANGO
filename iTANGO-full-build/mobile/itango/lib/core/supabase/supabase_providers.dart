// lib/core/supabase/supabase_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Single source of truth for the Supabase client. Every data layer
/// (auth, events, tickets, messaging) reads from this provider rather than
/// calling `Supabase.instance.client` directly, so tests can override it
/// with a fake/mock client.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Streams the current auth state (signed in / signed out / token refreshed)
/// so the router and UI can react reactively rather than polling.
final authStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

/// Convenience provider: the current user, or null if signed out.
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.value?.session?.user ?? Supabase.instance.client.auth.currentUser;
});
