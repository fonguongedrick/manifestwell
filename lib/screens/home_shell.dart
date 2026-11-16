import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../utils/haptics.dart';
import '../widgets/backdrop.dart';
import '../widgets/cast_ritual.dart';
import '../widgets/glyphs.dart';
import '../widgets/sheets.dart';
import 'paywall_screen.dart';
import 'settings_screen.dart';
import 'vault_screen.dart';
import 'well_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  bool _immersive = false;
  late final ValueNotifier<int?> _openTab;

  @override
  void initState() {
    super.initState();
    // A notification tap asks for a tab. It may have arrived before this
    // screen existed (the tap launched the app), so look once straight away.
    _openTab = context.read<AppState>().openTab..addListener(_onTabRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTabRequested());
  }

  @override
  void dispose() {
    _openTab.removeListener(_onTabRequested);
    super.dispose();
  }

  void _onTabRequested() {
    final tab = _openTab.value;
    if (tab == null || !mounted) return;
    _openTab.value = null;
    _go(tab);
  }

  void _go(int i) {
    if (i != _tab) setState(() => _tab = i);
  }

  /// After the first wish goes into the Well is the moment notifications make
  /// sense to the person, so that is the one time we ask.
  Future<void> _offerPush() async {
    final state = context.read<AppState>();
    if (!state.shouldOfferPush) return;
    await state.markPushAsked();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    if (!await showPushOfferSheet(context) || !mounted) return;
    final ok = await state.setPush(luck: true, revisit: true);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Notifications are off for ManifestWell. You can turn them on in your phone settings.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      WellScreen(onCast: () => _go(1), onOpenVault: () => _go(2)),
      SafeArea(
        child: CastRitual(
          onFinished: () {
            _go(0);
            _offerPush();
          },
          onImmersive: (v) => setState(() => _immersive = v),
          onPaywall: () => PaywallScreen.show(context),
        ),
      ),
      VaultScreen(onCast: () => _go(1)),
      const SettingsScreen(),
    ];
    return Scaffold(
      extendBody: true,
      body: Backdrop(
        moon: _tab != 2,
        child: Stack(children: [
          IndexedStack(index: _tab, children: pages),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: _immersive,
              child: AnimatedSlide(
                offset: _immersive ? const Offset(0, 1.2) : Offset.zero,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeInOutCubic,
                child: AnimatedOpacity(
                  opacity: _immersive ? 0 : 1,
                  duration: const Duration(milliseconds: 300),
                  child: _NavBar(index: _tab, onSelect: _go),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _NavBar({required this.index, required this.onSelect});

  static const _items = [
    ('Well', GlyphKind.house),
    ('Cast', GlyphKind.starPlus),
    ('Vault', GlyphKind.chest),
    ('Settings', GlyphKind.gear),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: EdgeInsets.fromLTRB(8, 10, 8, bottom + 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1248).withValues(alpha: 0.78),
            border: const Border(top: BorderSide(color: Color(0x40FFFFFF))),
          ),
          child: Row(children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: _NavItem(
                  label: _items[i].$1,
                  glyph: _items[i].$2,
                  selected: index == i,
                  onTap: () => onSelect(i),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final GlyphKind glyph;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.label,
    required this.glyph,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFFCDB0FF) : const Color(0xFFB9AEDF);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('tab-${label.toLowerCase()}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!selected) Haptics.selection();
          onTap();
        },
        child: SizedBox(
          height: 54,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: selected
                    ? [BoxShadow(color: MW.violet.withValues(alpha: 0.65), blurRadius: 18, spreadRadius: -2)]
                    : null,
              ),
              child: Glyph(glyph, size: 27, color: color, filled: selected, stroke: 1.7),
            ),
            const SizedBox(height: 4),
            Text(label, style: MW.ui(11.5, color: color, weight: selected ? 800 : 600)),
          ]),
        ),
      ),
    );
  }
}
