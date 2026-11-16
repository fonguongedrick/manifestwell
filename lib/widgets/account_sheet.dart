import 'package:flutter/foundation.dart' show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'ui.dart';

/// Lets a guest sign in later, from Settings. Closes itself on success.
Future<void> showAccountSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: MW.inkDeep,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _AccountSheet(),
    );

class _AccountSheet extends StatefulWidget {
  const _AccountSheet();

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  bool _busy = false;

  bool get _showApple =>
      defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;

  Future<void> _signIn(Future<bool> Function(AppState) attempt) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final ok = await attempt(state);
      if (ok && mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Sign-in failed: $e');
      messenger.showSnackBar(const SnackBar(content: Text('Could not sign in. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(MW.gutter, 22, MW.gutter, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SIGN IN', style: MW.display(22)),
          const SizedBox(height: 6),
          Text('Your wishes and proof follow you to any phone. Others never see who you are.',
              style: MW.ui(14, color: MW.textDim, height: 1.45)),
          const SizedBox(height: 20),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(color: MW.lilac)),
            )
          else ...[
            if (_showApple) ...[
              SocialButton(
                label: 'Continue with Apple',
                assetPath: 'assets/images/apple.png',
                onPressed: () => _signIn((s) => s.signInWithApple()),
              ),
              const SizedBox(height: 12),
            ],
            SocialButton(
              label: 'Continue with Google',
              assetPath: 'assets/images/google.png',
              onPressed: () => _signIn((s) => s.signInWithGoogle()),
            ),
          ],
        ]),
      ),
    );
  }
}
