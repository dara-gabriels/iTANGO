// lib/features/auth/domain/auth_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

/// Represents the phone-OTP flow's state machine — the presentation layer
/// only needs to render based on this, never touch Supabase types directly.
sealed class PhoneAuthState {
  const PhoneAuthState();
}
class PhoneAuthIdle extends PhoneAuthState { const PhoneAuthIdle(); }
class PhoneAuthSendingOtp extends PhoneAuthState { const PhoneAuthSendingOtp(); }
class PhoneAuthOtpSent extends PhoneAuthState { const PhoneAuthOtpSent(); }
class PhoneAuthVerifying extends PhoneAuthState { const PhoneAuthVerifying(); }
class PhoneAuthError extends PhoneAuthState {
  const PhoneAuthError(this.message);
  final String message;
}
class PhoneAuthSuccess extends PhoneAuthState { const PhoneAuthSuccess(); }

class AuthController extends StateNotifier<PhoneAuthState> {
  AuthController(this._repository) : super(const PhoneAuthIdle());
  final AuthRepository _repository;

  Future<void> requestOtp(String phoneNumber) async {
    state = const PhoneAuthSendingOtp();
    try {
      await _repository.sendPhoneOtp(phoneNumber);
      state = const PhoneAuthOtpSent();
    } catch (e) {
      state = PhoneAuthError(_friendlyError(e));
    }
  }

  Future<void> verifyOtp({required String phoneNumber, required String code}) async {
    state = const PhoneAuthVerifying();
    try {
      await _repository.verifyPhoneOtp(phoneNumber: phoneNumber, otpCode: code);
      state = const PhoneAuthSuccess();
    } catch (e) {
      state = PhoneAuthError(_friendlyError(e));
    }
  }

  String _friendlyError(Object e) {
    // Supabase surfaces provider-specific messages; map the common ones to
    // copy a non-technical user can act on rather than leaking raw API text.
    final raw = e.toString();
    if (raw.contains('Invalid OTP') || raw.contains('token')) {
      return "That code didn't match. Check it and try again.";
    }
    if (raw.contains('rate limit') || raw.contains('429')) {
      return "Too many attempts — wait a minute before trying again.";
    }
    return "Something went wrong. Please try again.";
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, PhoneAuthState>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});
