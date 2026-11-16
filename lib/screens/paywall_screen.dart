import 'package:flutter/foundation.dart' show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/links.dart';
import '../state/app_state.dart';
import '../state/subscriptions.dart';
import '../theme.dart';
import '../utils/haptics.dart';
import '../widgets/backdrop.dart';
import '../widgets/effects.dart';
import '../widgets/glyphs.dart';
import '../widgets/ui.dart';

/// ManifestWell Plus: shown when a free person tries to hold a second active
/// Big Wish, and from Settings. Prices, trials and availability all come from
/// the store; nothing here is hard-coded.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  static Future<void> show(BuildContext context) => Navigator.of(context).push(
        PageRouteBuilder<void>(
          fullscreenDialog: true,
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, _, _) => const PaywallScreen(),
          transitionsBuilder: (_, a, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
                  .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
        ),
      );

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  List<Plan>? _plans; // null while loading
  Plan? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _plans = null);
    final state = context.read<AppState>();
    final plans = state.purchasesAvailable ? await state.loadPlans() : const <Plan>[];
    if (!mounted) return;
    setState(() {
      _plans = plans;
      // Monthly is the usual starting point; otherwise the first on offer.
      _selected = plans.where((p) => p.period == 'month').firstOrNull ?? plans.firstOrNull;
    });
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _buy() async {
    final plan = _selected;
    if (plan == null || _busy) return;
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final result = await state.buyPlan(plan);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result.outcome) {
      case PurchaseOutcome.success:
        Haptics.heavy();
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('Welcome to Plus. Hold every dream at once.')));
      case PurchaseOutcome.cancelled:
        break; // They changed their mind; say nothing.
      case PurchaseOutcome.pending:
        _toast('Your purchase is waiting for approval. Plus unlocks as soon as it clears.');
      case PurchaseOutcome.failed:
        _toast(result.message ?? 'The purchase could not be completed.');
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final active = await state.restorePurchases();
      if (!mounted) return;
      if (active) {
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('Plus restored. Welcome back.')));
      } else {
        _toast('We could not find an active Plus subscription for this account.');
      }
    } catch (e) {
      debugPrint('Restore failed: $e');
      _toast('Could not reach the store. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) _toast('Could not open the link.');
    } catch (_) {
      _toast('Could not open the link.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      body: Backdrop(
        image: SkyImage.galaxy,
        child: SafeArea(
          child: LoadingOverlay(
            isLoading: _busy,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(MW.gutter, 12, MW.gutter, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: RoundIconButton(
                    glyph: GlyphKind.close,
                    semanticLabel: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              Expanded(child: state.isPro ? _active(state) : _offer(state)),
            ]),
          ),
        ),
      ),
    );
  }

  // ---- Already Plus ---------------------------------------------------------

  Widget _active(AppState state) => ListView(
        padding: const EdgeInsets.fromLTRB(MW.gutter, 24, MW.gutter, 24),
        children: [
          const Center(child: GlowOrb(size: 52, golden: true)),
          const SizedBox(height: 32),
          const Caps('ManifestWell Plus', color: MW.gold),
          const SizedBox(height: 14),
          Text('You are on Plus.', style: MW.display(28)),
          const SizedBox(height: 12),
          Text(
            'Thank you for supporting ManifestWell. You can hold as many Big Wishes as you like.',
            style: MW.ui(15, color: MW.textDim, height: 1.5),
          ),
          const SizedBox(height: 28),
          GlowButton('Manage subscription', onPressed: () async => _open(await state.manageSubscriptionUrl())),
          QuietLink('Done', onPressed: () => Navigator.of(context).pop()),
        ],
      );

  // ---- The offer ------------------------------------------------------------

  Widget _offer(AppState state) {
    final plans = _plans;
    return Column(children: [
      Expanded(
        child: ListView(
          clipBehavior: Clip.none,
          padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 16),
          children: [
            const Center(child: GlowOrb(size: 44, golden: true)),
            const SizedBox(height: 28),
            const Caps('ManifestWell Plus', color: MW.gold),
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Hold every dream '),
                TextSpan(text: 'at once.', style: MW.display(28, color: MW.goldBright)),
              ]),
              style: MW.display(28),
            ),
            const SizedBox(height: 12),
            Text(
              'Your first Big Wish is always free. Plus lets you keep as many as you like glowing together: career, love, home, health and travel, all at once.',
              style: MW.ui(15, color: MW.textDim, height: 1.5),
            ),
            const SizedBox(height: 24),
            if (plans == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator(color: MW.lilac)),
              )
            else if (plans.isEmpty)
              _Unavailable(
                message: state.purchasesAvailable
                    ? 'We could not load the plans. Check your connection and try again.'
                    : 'Subscriptions are not available in this version yet.',
                onRetry: state.purchasesAvailable ? _load : null,
              )
            else
              for (final p in plans) ...[
                _PlanTile(
                  key: ValueKey('plan-${p.id}'),
                  plan: p,
                  selected: _selected?.id == p.id,
                  onTap: () => setState(() => _selected = p),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
      if (plans != null && plans.isNotEmpty) _footer(),
    ]);
  }

  Widget _footer() {
    final plan = _selected;
    final trial = plan?.trial;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    // The disclosures both stores require next to a subscription purchase.
    final legal = ios
        ? 'Payment is charged to your Apple ID at confirmation of purchase. The subscription renews '
            'automatically unless it is cancelled at least 24 hours before the end of the current period, '
            'and your account is charged for renewal within 24 hours before the period ends. Manage or '
            'cancel any time in your App Store account settings.'
        : 'Payment is charged to your Google Play account at confirmation of purchase. The subscription '
            'renews automatically unless it is cancelled before the end of the current period. Manage or '
            'cancel any time in Google Play, under Payments & subscriptions.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(MW.gutter, 4, MW.gutter, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        GlowButton(
          trial != null ? 'Start free trial' : 'Continue',
          key: const ValueKey('buy-button'),
          onPressed: plan == null ? null : _buy,
        ),
        if (plan != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              trial != null
                  ? '$trial, then ${plan.price} per ${plan.period}. Cancel any time.'
                  : '${plan.price} per ${plan.period}. Cancel any time.',
              textAlign: TextAlign.center,
              style: MW.ui(13, color: MW.textDim, weight: 700),
            ),
          ),
        const SizedBox(height: 2),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _FooterLink('Restore purchases', onTap: _restore),
          const _Dot(),
          _FooterLink('Terms', onTap: () => _open(Uri.parse(Links.terms))),
          const _Dot(),
          _FooterLink('Privacy', onTap: () => _open(Uri.parse(Links.privacy))),
        ]),
        Text(legal, textAlign: TextAlign.center, style: MW.ui(10.5, color: MW.textFaint, height: 1.4)),
      ]),
    );
  }
}

/// A small tappable text link with a comfortable touch area.
class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FooterLink(this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Text(label, style: MW.ui(13, color: MW.textDim, weight: 700)),
          ),
        ),
      );
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Text('·', style: MW.ui(13, color: MW.textFaint, weight: 800));
}

class _Unavailable extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _Unavailable({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Text(message, textAlign: TextAlign.center, style: MW.ui(15, color: MW.textDim, height: 1.5)),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            GlowButton('Try again', compact: true, expand: false, onPressed: onRetry),
          ],
        ]),
      );
}

class _PlanTile extends StatelessWidget {
  final Plan plan;
  final bool selected;
  final VoidCallback onTap;
  const _PlanTile({super.key, required this.plan, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: '${plan.title}, ${plan.price} per ${plan.period}${plan.trial == null ? '' : ', ${plan.trial}'}',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.selection();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: selected ? MW.gold.withValues(alpha: 0.10) : MW.glass,
              border: Border.all(
                color: selected ? MW.gold.withValues(alpha: 0.9) : MW.hairline,
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected ? [BoxShadow(color: MW.gold.withValues(alpha: 0.18), blurRadius: 24)] : null,
            ),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? MW.gold : MW.textFaint, width: 1.6),
                  color: selected ? MW.gold : Colors.transparent,
                ),
                child: selected ? const Glyph(GlyphKind.check, size: 14, color: MW.ink, stroke: 2.2) : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(plan.title, style: MW.ui(17, color: MW.text, weight: 800)),
                  if (plan.trial != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(plan.trial!, style: MW.ui(13, color: MW.goldBright, weight: 700)),
                    ),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(plan.price, style: MW.display(22)),
                Text('per ${plan.period}', style: MW.ui(12, color: MW.textFaint, weight: 600)),
              ]),
            ]),
          ),
        ),
      );
}
