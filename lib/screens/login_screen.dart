import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_service.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/dot_shader_background.dart';
import '../widgets/footer.dart';
import '../widgets/ui.dart';

/// Port of pages/Login.jsx — always dark, dot-shader background, Google sign-in.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _signingIn = false;
  String _error = '';

  Future<void> _login() async {
    setState(() {
      _signingIn = true;
      _error = '';
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      // The router redirects once the auth state updates
    } catch (e) {
      debugPrint('Error logging in with Google: $e');
      if (mounted) setState(() => _error = loginErrorMessage(e));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    return Theme(
      data: buildTheme(AppColors.dark),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: Stack(children: [
            if (!reducedMotion) const Positioned.fill(child: DotShaderBackground()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    // IntrinsicHeight gives the Column a finite height inside the scroll view,
                    // so the card stays centred and the footer pinned to the bottom
                    child: IntrinsicHeight(
                      child: Column(children: [
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 448),
                              child: Padding(padding: const EdgeInsets.all(16), child: _content(context)),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          child: Footer(color: AppColors.zinc400),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final c = context.colors;
    final linkStyle = inter(size: FontSizes.xs, color: c.news, decoration: TextDecoration.underline);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('BudgetMate',
          textAlign: TextAlign.center,
          style: inter(size: FontSizes.x4l, weight: FontWeight.w700, color: Colors.white, letterSpacing: -0.9, height: 1.1)),
      const SizedBox(height: 8),
      Text('Track expenses, scan receipts and split bills',
          textAlign: TextAlign.center, style: inter(size: FontSizes.lg, weight: FontWeight.w500, color: AppColors.zinc300)),
      const SizedBox(height: 32),
      AppCard(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const CardTitle('Welcome'),
              const SizedBox(height: 6),
              const CardDescription('Sign in with your Google account to continue', textAlign: TextAlign.center),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(spacing: 16, children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: AppButton(
                  onPressed: _login,
                  loading: _signingIn,
                  label: _signingIn ? 'Signing in…' : 'Sign in with Google',
                  radius: Radii.md,
                  expand: true,
                ),
              ),
              if (_error.isNotEmpty)
                Text(_error, textAlign: TextAlign.center, style: inter(size: FontSizes.sm, color: AppColors.red400)),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'By signing in you agree to our '),
                    TextSpan(text: 'Terms', style: linkStyle, recognizer: TapGestureRecognizer()..onTap = () => openLegalPage(context, '/terms')),
                    const TextSpan(text: '. Learn how we handle your data in our '),
                    TextSpan(
                        text: 'Privacy Policy',
                        style: linkStyle,
                        recognizer: TapGestureRecognizer()..onTap = () => openLegalPage(context, '/privacy')),
                    const TextSpan(text: '.'),
                  ]),
                  textAlign: TextAlign.center,
                  style: inter(size: FontSizes.xs, color: c.news),
                ),
              ),
            ]),
          ),
        ]),
      ),
    ]);
  }
}
