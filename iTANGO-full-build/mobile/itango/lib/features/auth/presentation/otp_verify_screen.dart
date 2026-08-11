// lib/features/auth/presentation/otp_verify_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/itango_theme.dart';
import '../domain/auth_controller.dart';

class OtpVerifyScreen extends ConsumerStatefulWidget {
  const OtpVerifyScreen({super.key, required this.phoneNumber});
  final String phoneNumber;

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isVerifying = authState is PhoneAuthVerifying;

    ref.listen(authControllerProvider, (previous, next) {
      if (next is PhoneAuthError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.message), backgroundColor: ItangoColors.statusDanger),
        );
      }
      // On PhoneAuthSuccess, the router's redirect logic (app_router.dart)
      // picks up the auth state change automatically via authStateProvider
      // — no explicit navigation call needed here.
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your number')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ItangoSpacing.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the code sent to ${widget.phoneNumber}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: ItangoSpacing.s5),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(fontSize: 24, letterSpacing: 8, color: ItangoColors.textPrimary),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(counterText: '', hintText: '••••••'),
              ),
              const SizedBox(height: ItangoSpacing.s5),
              isVerifying
                  ? const Center(child: CircularProgressIndicator(color: ItangoColors.brandPrimary))
                  : ItangoGradientButton(
                      label: 'Verify',
                      onPressed: () => ref.read(authControllerProvider.notifier).verifyOtp(
                            phoneNumber: widget.phoneNumber,
                            code: _codeController.text.trim(),
                          ),
                    ),
              const SizedBox(height: ItangoSpacing.s4),
              TextButton(
                onPressed: () => ref.read(authControllerProvider.notifier).requestOtp(widget.phoneNumber),
                child: const Text('Resend code', style: TextStyle(color: ItangoColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
