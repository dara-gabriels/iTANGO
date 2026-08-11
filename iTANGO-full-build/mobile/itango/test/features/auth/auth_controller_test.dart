// test/features/auth/auth_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:itango/features/auth/data/auth_repository.dart';
import 'package:itango/features/auth/domain/auth_controller.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

/// mocktail's Fake, not Mock — we never access any member of the returned
/// AuthResponse in AuthController.verifyOtp (it only awaits the call), so a
/// Fake that throws if touched is the correct minimal stand-in rather than
/// guessing at AuthResponse's real constructor signature.
class FakeAuthResponse extends Fake implements AuthResponse {}

void main() {
  late MockAuthRepository mockRepository;
  late AuthController controller;

  setUp(() {
    mockRepository = MockAuthRepository();
    controller = AuthController(mockRepository);
  });

  group('AuthController.requestOtp', () {
    test('transitions Idle -> SendingOtp -> OtpSent on success', () async {
      when(() => mockRepository.sendPhoneOtp(any())).thenAnswer((_) async {});

      expect(controller.state, isA<PhoneAuthIdle>());

      final future = controller.requestOtp('+2348012345678');
      // Immediately after calling, before the await resolves, state should
      // already be SendingOtp — this is the whole point of testing a state
      // machine: the intermediate state matters for what the UI shows
      // during the async gap, not just the eventual result.
      expect(controller.state, isA<PhoneAuthSendingOtp>());

      await future;
      expect(controller.state, isA<PhoneAuthOtpSent>());
      verify(() => mockRepository.sendPhoneOtp('+2348012345678')).called(1);
    });

    test('transitions to Error with a friendly message on rate-limit failure', () async {
      when(() => mockRepository.sendPhoneOtp(any()))
          .thenThrow(Exception('AuthException: rate limit exceeded, 429'));

      await controller.requestOtp('+2348012345678');

      expect(controller.state, isA<PhoneAuthError>());
      final errorState = controller.state as PhoneAuthError;
      // Asserting the friendly message specifically — this is the whole
      // reason _friendlyError() exists rather than surfacing raw Supabase
      // exception text to the user; a test that only checked "is an error
      // state" would miss a regression that leaked the raw message.
      expect(errorState.message, contains('Too many attempts'));
    });

    test('maps an invalid-OTP failure to a distinct, actionable message', () async {
      when(() => mockRepository.sendPhoneOtp(any()))
          .thenThrow(Exception('Invalid OTP token'));

      await controller.requestOtp('+2348012345678');

      final errorState = controller.state as PhoneAuthError;
      expect(errorState.message, contains("didn't match"));
    });

    test('falls back to a generic message for an unrecognized error shape', () async {
      when(() => mockRepository.sendPhoneOtp(any())).thenThrow(Exception('some unexpected internal error'));

      await controller.requestOtp('+2348012345678');

      final errorState = controller.state as PhoneAuthError;
      expect(errorState.message, 'Something went wrong. Please try again.');
    });
  });

  group('AuthController.verifyOtp', () {
    test('transitions Idle -> Verifying -> Success on valid code', () async {
      when(() => mockRepository.verifyPhoneOtp(
            phoneNumber: any(named: 'phoneNumber'),
            otpCode: any(named: 'otpCode'),
          )).thenAnswer((_) async => FakeAuthResponse());

      final future = controller.verifyOtp(phoneNumber: '+2348012345678', code: '123456');
      expect(controller.state, isA<PhoneAuthVerifying>());

      await future;
      expect(controller.state, isA<PhoneAuthSuccess>());
      verify(() => mockRepository.verifyPhoneOtp(
            phoneNumber: '+2348012345678',
            otpCode: '123456',
          )).called(1);
    });

    test('transitions to Error when the code is wrong', () async {
      when(() => mockRepository.verifyPhoneOtp(
            phoneNumber: any(named: 'phoneNumber'),
            otpCode: any(named: 'otpCode'),
          )).thenThrow(Exception('Invalid OTP token'));

      await controller.verifyOtp(phoneNumber: '+2348012345678', code: '000000');

      expect(controller.state, isA<PhoneAuthError>());
    });
  });
}
