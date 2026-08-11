// lib/features/auth/presentation/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/itango_theme.dart';
import '../../../core/router/app_router.dart';
import '../domain/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _continueWithPhone() async {
    final phone = _phoneController.text.trim();
    if (!_isValidPhone(phone)) {
      setState(() => _validationError = 'Enter a valid phone number, e.g. +2348012345678');
      return;
    }
    setState(() => _validationError = null);

    await ref.read(authControllerProvider.notifier).requestOtp(phone);
    final state = ref.read(authControllerProvider);
    if (state is PhoneAuthOtpSent && mounted) {
      context.push(AppRoutes.otpVerify, extra: phone);
    }
  }

  bool _isValidPhone(String phone) => RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone);

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState is PhoneAuthSendingOtp;

    ref.listen(authControllerProvider, (previous, next) {
      if (next is PhoneAuthError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.message), backgroundColor: ItangoColors.statusDanger),
        );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: ItangoSpacing.s16),
              // Wordmark uses the brand serif — the one place in the app
              // where we deliberately break from the Inter-everywhere rule,
              // matching the logo's typographic identity.
              const Text(
                'iTango',
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: ItangoColors.textPrimary,
                ),
              ),
              const SizedBox(height: ItangoSpacing.s2),
              Text(
                'Own the Night',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ItangoColors.textSecondary,
                      letterSpacing: 1.2,
                    ),
              ),
              const SizedBox(height: ItangoSpacing.s12),
              Text('Enter your phone number', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: ItangoSpacing.s3),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: ItangoColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '+234 801 234 5678',
                  errorText: _validationError,
                ),
              ),
              const SizedBox(height: ItangoSpacing.s5),
              isLoading
                  ? const Center(child: CircularProgressIndicator(color: ItangoColors.brandPrimary))
                  : ItangoGradientButton(label: 'Continue', onPressed: _continueWithPhone),
              const SizedBox(height: ItangoSpacing.s6),
              Row(
                children: [
                  const Expanded(child: Divider(color: ItangoColors.borderSubtle)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s3),
                    child: Text('or', style: Theme.of(context).textTheme.bodySmall),
                  ),
                  const Expanded(child: Divider(color: ItangoColors.borderSubtle)),
                ],
              ),
              const SizedBox(height: ItangoSpacing.s6),
              _SocialButton(label: 'Continue with Google', onPressed: () {
                ref.read(authRepositoryProvider).signInWithGoogle();
              }),
              const SizedBox(height: ItangoSpacing.s3),
              _SocialButton(label: 'Continue with Apple', onPressed: () {
                ref.read(authRepositoryProvider).signInWithApple();
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: ItangoColors.borderDefault),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ItangoRadius.pill)),
      ),
      child: Text(label, style: const TextStyle(color: ItangoColors.textPrimary, fontWeight: FontWeight.w600)),
    );
  }
}
