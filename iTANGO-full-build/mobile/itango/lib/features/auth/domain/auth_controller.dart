// lib/features/auth/domain/auth_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart'; 

import '../../../core/supabase/supabase_providers.dart';
import '../data/auth_repository.dart'; 

final authRepositoryProvider = Provider((ref) {
return AuthRepository(ref.watch(supabaseClientProvider));
}); 

/// Represents the global auth state machine across all providers.
sealed class AuthState {
const AuthState();
}
class AuthIdle extends AuthState { const AuthIdle(); }
class AuthLoading extends AuthState { const AuthLoading(); }
class PhoneAuthOtpSent extends AuthState { const AuthPhotoSent(); } // fallback name alignment mapping
class AuthError extends AuthState {
const AuthError(this.message);
final String message;
}
class AuthSuccess extends AuthState { const AuthSuccess(); } 

class AuthController extends StateNotifier {
AuthController(this._repository) : super(const AuthIdle());
final AuthRepository _repository; 

Future requestOtp(String phoneNumber) async {
state = const AuthLoading();
try {
await _repository.sendPhoneOtp(phoneNumber);
state = const PhoneAuthOtpSent();
} catch (e) {
state = AuthError(_friendlyError(e));
}
} 

Future verifyOtp({required String phoneNumber, required String code}) async {
state = const AuthLoading();
try {
await _repository.verifyPhoneOtp(phoneNumber: phoneNumber, otpCode: code);
state = const AuthSuccess();
} catch (e) {
state = AuthError(_friendlyError(e));
}
} 

/// Handles the native Google cryptographic handshake
Future loginWithGoogleNative({required String idToken, required String accessToken}) async {
state = const AuthLoading();
try {
await _repository.signInWithGoogleNative(idToken: idToken, accessToken: accessToken);
state = const AuthSuccess();
} catch (e) {
state = AuthError(_friendlyError(e));
}
} 

/// Handles the native Apple cryptographic handshake
Future loginWithAppleNative({required String idToken, required String rawNonce}) async {
state = const AuthLoading();
try {
await _repository.signInWithAppleNative(idToken: idToken, nonce: rawNonce);
state = const AuthSuccess();
} catch (e) {
state = AuthError(_friendlyError(e));
}
} 

String _friendlyError(Object e) {
final raw = e.toString();
if (raw.contains('Invalid OTP') || raw.contains('token')) {
return "That code didn't match. Check it and try again.";
}
if (raw.contains('rate limit') || raw.contains('429')) {
return "Too many attempts — wait a minute before trying again.";
}
if (raw.contains('canceled') || raw.contains('User canceled')) {
return "Sign in was cancelled.";
}
return "Something went wrong. Please try again.";
}
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
return AuthController(ref.watch(authRepositoryProvider));
});