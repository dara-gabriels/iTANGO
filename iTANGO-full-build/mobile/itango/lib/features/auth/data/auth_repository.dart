// lib/features/auth/data/auth_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Supabase Auth so the presentation layer never calls
/// Supabase.instance.client.auth directly — this is the seam we'd swap if
/// iTANGO ever moved off Supabase Auth (Clean Architecture boundary).
class AuthRepository {
AuthRepository(this._client);
final SupabaseClient _client;

/// Step 1 of phone auth: request an OTP be sent via SMS.
Future sendPhoneOtp(String phoneNumber) async {
await _client.auth.signInWithOtp(phone: phoneNumber);
}

/// Step 2: verify the code the user received.
Future verifyPhoneOtp({
required String phoneNumber,
required String otpCode,
}) {
return _client.auth.verifyOTP(
type: OtpType.sms,
phone: phoneNumber,
token: otpCode,
);
}

Future sendEmailOtp(String email) async {
await _client.auth.signInWithOtp(email: email);
}

Future verifyEmailOtp({
required String email,
required String otpCode,
}) {
return _client.auth.verifyOTP(
type: OtpType.email,
email: email,
token: otpCode,
);
}

/// Sign in using a native Google ID Token retrieved via the google_sign_in package.
/// This bypasses external web views completely for a seamless native overlay.
Future signInWithGoogleNative({
required String idToken,
required String accessToken,
}) {
return _client.auth.signInWithIdToken(
provider: OAuthProvider.google,
idToken: idToken,
accessToken: accessToken,
);
}

/// Sign in using a native Apple Identity Token retrieved via the sign_in_with_apple package.
Future signInWithAppleNative({
required String idToken,
required String rawNonce,
}) {
return _client.auth.signInWithIdToken(
provider: OAuthProvider.apple,
idToken: idToken,
nonce: rawNonce,
);
}

Future signOut() => _client.auth.signOut();

bool get isSignedIn => _client.auth.currentSession != null;
}