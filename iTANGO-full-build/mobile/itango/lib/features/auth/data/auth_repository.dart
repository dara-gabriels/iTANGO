// lib/features/auth/data/auth_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Supabase Auth so the presentation layer never calls
/// `Supabase.instance.client.auth` directly — this is the seam we'd swap if
/// iTANGO ever moved off Supabase Auth (Clean Architecture boundary).
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  /// Step 1 of phone auth: request an OTP be sent via SMS.
  Future<void> sendPhoneOtp(String phoneNumber) async {
    await _client.auth.signInWithOtp(phone: phoneNumber);
  }

  /// Step 2: verify the code the user received.
  Future<AuthResponse> verifyPhoneOtp({
    required String phoneNumber,
    required String otpCode,
  }) {
    return _client.auth.verifyOTP(
      type: OtpType.sms,
      phone: phoneNumber,
      token: otpCode,
    );
  }

  Future<void> sendEmailOtp(String email) async {
    await _client.auth.signInWithOtp(email: email);
  }

  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String otpCode,
  }) {
    return _client.auth.verifyOTP(
      type: OtpType.email,
      email: email,
      token: otpCode,
    );
  }

  /// Google/Apple sign-in open a native OAuth flow; Supabase handles the
  /// token exchange. `redirectTo` must be registered in Supabase Auth
  /// settings and match the app's deep link scheme (itango://login-callback).
  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'itango://login-callback',
    );
  }

  Future<bool> signInWithApple() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: 'itango://login-callback',
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  bool get isSignedIn => _client.auth.currentSession != null;
}
