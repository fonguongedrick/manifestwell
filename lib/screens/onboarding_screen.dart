import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/backdrop.dart';
import '../widgets/cast_ritual.dart';
import '../widgets/effects.dart';
import '../widgets/glyphs.dart';
import '../widgets/ui.dart';
import '../widgets/well_painter.dart';
import 'paywall_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 5;
  final _pages = PageController();
  int _index = 0;
  bool _signingIn = false;
  TimeOfDay _time = const TimeOfDay(hour: 19, minute: 0);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() => _pages.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );

  Future<void> _finish({required bool remind}) async {
    final state = context.read<AppState>();
    // TODO(notifications): request OS permission and schedule the daily nudge
    // (FCM / local notifications) here. Only the preference is stored today.
    await state.setReminder(hour: _time.hour, minute: _time.minute, enabled: remind);
    await state.completeOnboarding();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Runs a provider sign-in. Dismissing the system sheet is not an error, so
  /// it just stays on the page; anything else tells the person and lets them
  /// carry on as a guest.
  Future<void> _signIn(Future<bool> Function(AppState) attempt) async {
    final state = context.read<AppState>();
    if (!state.hasBackend) {
      _toast('Sign-in needs an internet connection. You can continue as a guest.');
      return;
    }
    setState(() => _signingIn = true);
    try {
      final ok = await attempt(state);
      if (ok && mounted) _next();
    } catch (e) {
      debugPrint('Sign-in failed: $e');
      if (mounted) _toast('Could not sign in. Please try again, or continue as a guest.');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  void _goToSignIn() => _pages.animateToPage(
        2,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );

  // Apple sign-in on Android needs a separate web setup, so it is offered on
  // Apple devices only.
  bool get _showApple =>
      defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Backdrop(
        image: SkyImage.spiral,
        moon: _index == 0,
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(MW.gutter, 14, MW.gutter, 0),
              child: Row(children: [
                for (var i = 0; i < _pageCount; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      height: 2.5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: i <= _index ? MW.gold : Colors.white.withValues(alpha: 0.14),
                        boxShadow: i == _index
                            ? [BoxShadow(color: MW.gold.withValues(alpha: 0.7), blurRadius: 8)]
                            : null,
                      ),
                    ),
                  ),
                ],
              ]),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _welcome(),
                  const _Concept(),
                  _auth(),
                  _firstWish(),
                  _reminder(),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // 1 -------------------------------------------------------------------

  Widget _welcome() => Padding(
        padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Spacer(flex: 2),
          const Center(child: _OrbWithRings()),
          const Spacer(),
          Reveal(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Caps('Welcome to ManifestWell', color: MW.gold),
              const SizedBox(height: 18),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Everything always '),
                  TextSpan(
                    text: 'works out for you.',
                    style: MW.display(32, color: MW.goldBright),
                  ),
                ]),
                style: MW.display(32),
              ),
              const SizedBox(height: 18),
              Text(
                'Step into a world where your hopes are held by thousands, and every good thing is counted.',
                style: MW.ui(16, color: MW.textDim, height: 1.55),
              ),
            ]),
          ),
          const SizedBox(height: 36),
          GlowButton('Begin your ritual', onPressed: _next),
          QuietLink('I already have an account', onPressed: _goToSignIn),
        ]),
      );

  // 3 -------------------------------------------------------------------

  Widget _auth() => LoadingOverlay(
        isLoading: _signingIn,
        child: Padding(
        padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Spacer(),
          const Caps('Your space', color: MW.gold),
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Choose your '),
              TextSpan(
                text: 'energy space.',
                style: MW.display(30, color: MW.goldBright),
              ),
            ]),
            style: MW.display(30),
          ),
          const SizedBox(height: 14),
          Text('Sign in so your wishes and proof follow you to any phone, or simply begin. Others never see who you are.',
              style: MW.ui(15, color: MW.textDim, height: 1.55)),
          const SizedBox(height: 40),
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
          const SizedBox(height: 22),
          Row(children: [
            const Expanded(child: Hairline()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text('or', style: MW.ui(13, color: MW.textFaint)),
            ),
            const Expanded(child: Hairline()),
          ]),
          const SizedBox(height: 22),
          GlowButton('Continue as guest', onPressed: _next),
          const Spacer(),
        ]),
        ),
      );

  // 4 -------------------------------------------------------------------

  Widget _firstWish() => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(MW.gutter, 22, MW.gutter, 18),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Caps('Your first wish', color: MW.gold),
          ),
        ),
        Expanded(
          child: CastRitual(
            finishedLabel: 'Continue',
            allowAnother: false,
            onFinished: _next,
            onPaywall: () => PaywallScreen.show(context),
          ),
        ),
      ]);

  // 5 -------------------------------------------------------------------

  Widget _reminder() => Padding(
        padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Spacer(),
          const _NotificationPreview(),
          const SizedBox(height: 40),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Never miss your '),
              TextSpan(
                text: 'daily spark.',
                style: MW.display(30, color: MW.goldBright),
              ),
            ]),
            style: MW.display(30),
          ),
          const SizedBox(height: 14),
          Text(
            'A gentle nudge to notice what went right, and to know when someone sends luck to your wish.',
            style: MW.ui(15, color: MW.textDim, height: 1.55),
          ),
          const SizedBox(height: 30),
          const Hairline(),
          Semantics(
            button: true,
            label: 'Change check-in time',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _time);
                if (t != null) setState(() => _time = t);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(children: [
                  const Expanded(child: Caps('Check in at', color: MW.textDim)),
                  Text(_time.format(context), style: MW.display(36, color: MW.goldBright)),
                  const SizedBox(width: 6),
                  const Glyph(GlyphKind.chevronRight, size: 18, color: MW.textFaint),
                ]),
              ),
            ),
          ),
          const Hairline(),
          const Spacer(),
          GlowButton('Enable daily reminders', onPressed: () => _finish(remind: true)),
          QuietLink('Maybe later', onPressed: () => _finish(remind: false)),
        ]),
      );
}

/// Hero for the welcome page: an orb with slow rings spreading around it.
class _OrbWithRings extends StatefulWidget {
  const _OrbWithRings();

  @override
  State<_OrbWithRings> createState() => _OrbWithRingsState();
}

class _OrbWithRingsState extends State<_OrbWithRings> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 5));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 0.4;
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 300,
        height: 300,
        child: Stack(alignment: Alignment.center, children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(
              size: const Size(300, 300),
              painter: RingsPainter(_c.value, color: MW.violet),
            ),
          ),
          const GlowOrb(size: 74),
        ]),
      );
}

class _Concept extends StatefulWidget {
  const _Concept();

  @override
  State<_Concept> createState() => _ConceptState();
}

class _ConceptState extends State<_Concept> {
  static const _cards = [
    (GlyphKind.well, 'The Wishing Well', 'Release your wishes into a glowing, global well and receive real positive energy.'),
    (GlyphKind.constellation, 'The Proof Vault', 'Log your little wins and watch the evidence build, until your mind notices that good things keep happening.'),
    (GlyphKind.spark, 'The Ritual', 'Speak or write your hopes, then carry them to the well. Make wishing something you can feel.'),
  ];
  final _c = PageController();
  int _i = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _advance(BuildContext context) {
    if (_i < _cards.length - 1) {
      _c.nextPage(duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic);
    } else {
      context.findAncestorStateOfType<_OnboardingScreenState>()?._next();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
        child: Column(children: [
          Expanded(
            child: PageView.builder(
              controller: _c,
              itemCount: _cards.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (_, i) {
                final c = _cards[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MW.gutter),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Spacer(),
                    Center(
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: MW.gold.withValues(alpha: 0.35)),
                          gradient: RadialGradient(colors: [
                            MW.gold.withValues(alpha: 0.18),
                            MW.violet.withValues(alpha: 0.06),
                            Colors.transparent,
                          ]),
                        ),
                        alignment: Alignment.center,
                        child: Glyph(c.$1, size: 64, color: MW.goldBright, stroke: 1.2),
                      ),
                    ),
                    const SizedBox(height: 48),
                    Caps('0${i + 1} / 03', color: MW.gold),
                    const SizedBox(height: 14),
                    Text(c.$2.toUpperCase(), style: MW.display(28)),
                    const SizedBox(height: 14),
                    Text(c.$3, style: MW.ui(16, color: MW.textDim, height: 1.6)),
                    const Spacer(),
                  ]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MW.gutter),
            child: GlowButton(_i == _cards.length - 1 ? 'Continue' : 'Next',
                onPressed: () => _advance(context)),
          ),
        ]),
      );
}

class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview();

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(16),
        radius: 22,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A2468), MW.ink],
              ),
              border: Border.all(color: MW.hairline),
            ),
            alignment: Alignment.center,
            child: const Glyph(GlyphKind.spark, size: 20, color: MW.goldBright, filled: true),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('ManifestWell', style: MW.ui(13.5, color: MW.text, weight: 700))),
                Text('now', style: MW.ui(12, color: MW.textFaint)),
              ]),
              const SizedBox(height: 3),
              Text('What went right today? Take a moment to record one little win.',
                  style: MW.ui(13.5, color: MW.textDim, height: 1.4)),
            ]),
          ),
        ]),
      );
}
