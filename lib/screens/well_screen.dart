import 'package:flutter/material.dart';
import '../utils/haptics.dart';
import 'package:provider/provider.dart';

import '../data/affirmations.dart';
import '../models/wish.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/proof_row.dart';
import '../widgets/ui.dart';
import '../widgets/wish_entry.dart';

class WellScreen extends StatelessWidget {
  /// Switches to the Cast tab. The Well's composer stages its text first.
  final VoidCallback onCast;
  final VoidCallback onOpenVault;
  const WellScreen({super.key, required this.onCast, required this.onOpenVault});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final feed = state.feed;
    final proof = state.proof;
    final a = affirmationFor(DateTime.now());

    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverSafeArea(
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(MW.gutter + 4, 22, MW.gutter, 0),
              child: Reveal(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const GlowTitle('ManifestWell', size: 31),
                  const SizedBox(height: 10),
                  Text('${a.lead}${a.accent}', style: MW.ui(14.5, color: MW.textDim, weight: 600)),
                ]),
              ),
            ),
          ),
        ),
        if (state.config.banner.isNotEmpty || state.wishingPaused)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(MW.gutter, 20, MW.gutter, 0),
              child: _Notice(
                text: state.wishingPaused
                    ? 'New wishes are paused for a little while. You can still send luck.'
                    : state.config.banner,
                // When both apply, the pause matters more; the banner follows.
                extra: state.wishingPaused && state.config.banner.isNotEmpty ? state.config.banner : null,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(MW.gutter, 26, MW.gutter, 0),
            child: Reveal(
              delay: const Duration(milliseconds: 100),
              child: _MakeAWish(
                onCast: (text) {
                  if (text.isNotEmpty) state.stagePending(text);
                  onCast();
                },
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(MW.gutter + 2, 34, MW.gutter, 12),
            child: const SectionHeading('Recent wishes', glyph: GlyphKind.spark),
          ),
        ),
        SliverToBoxAdapter(child: _FilterChips(state: state)),
        if (feed.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Text(
                'The Well is quiet here.\nBe the first to cast a wish.',
                textAlign: TextAlign.center,
                style: TextStyle(color: MW.textDim, height: 1.6),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: feed.length,
            itemBuilder: (_, i) {
              final entry = WishEntry(key: ValueKey(feed[i].id), wish: feed[i]);
              return i < 4 ? Reveal(delay: Duration(milliseconds: 200 + i * 80), child: entry) : entry;
            },
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(MW.gutter + 2, 24, MW.gutter, 12),
            child: SectionHeading(
              'Grants & gratitude',
              glyph: GlyphKind.trophy,
              trailing: proof.isEmpty
                  ? null
                  : GestureDetector(
                      onTap: onOpenVault,
                      child: Text('See all', style: MW.ui(13.5, color: MW.lilac, weight: 800)),
                    ),
            ),
          ),
        ),
        if (proof.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 0),
              child: GlassCard(
                blur: 10,
                radius: 20,
                child: Text(
                  'When a wish comes true, or a little win happens, it is kept here as proof.',
                  style: MW.ui(14.5, color: MW.textDim, height: 1.5),
                ),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: proof.length.clamp(0, 3),
            itemBuilder: (_, i) => ProofRow(wish: proof[i], onTap: onOpenVault),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 130)),
      ],
    );
  }
}

/// A short message from the people who run the Well, set in the admin
/// dashboard.
class _Notice extends StatelessWidget {
  final String text;
  final String? extra;
  const _Notice({required this.text, this.extra});

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        liveRegion: true,
        child: GlassCard(
          radius: 20,
          blur: 10,
          borderColor: MW.gold.withValues(alpha: 0.5),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Glyph(GlyphKind.info, size: 18, color: MW.gold, stroke: 1.6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, style: MW.ui(14.5, color: MW.text, weight: 700, height: 1.4)),
                if (extra != null) ...[
                  const SizedBox(height: 6),
                  Text(extra!, style: MW.ui(13.5, color: MW.textDim, height: 1.4)),
                ],
              ]),
            ),
          ]),
        ),
      );
}

/// The "MAKE A WISH" card with its glowing input and the CAST YOUR WISH pill
/// straddling the bottom edge, as in the sample.
class _MakeAWish extends StatefulWidget {
  final ValueChanged<String> onCast;
  const _MakeAWish({required this.onCast});

  @override
  State<_MakeAWish> createState() => _MakeAWishState();
}

class _MakeAWishState extends State<_MakeAWish> {
  final _c = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _c.text.trim();
    _focus.unfocus();
    _c.clear();
    widget.onCast(text);
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return Stack(clipBehavior: Clip.none, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 30),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 50),
          radius: 28,
          child: Column(children: [
            const Center(child: SectionHeading('Make a wish', glyph: GlyphKind.spark)),
            const SizedBox(height: 16),
            Stack(clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: const Color(0x1AFFFFFF),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: MW.violet.withValues(alpha: focused ? 0.95 : 0.6),
                    width: 1.4,
                  ),
                  boxShadow: [BoxShadow(color: MW.violet.withValues(alpha: focused ? 0.45 : 0.22), blurRadius: 18)],
                ),
                child: TextField(
                  controller: _c,
                  focusNode: _focus,
                  minLines: 3,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  cursorColor: MW.lilac,
                  style: MW.voice(18, weight: 600),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'I wish to manifest my dream apartment in downtown NY…',
                    hintStyle: MW.voice(18, color: MW.textFaint, weight: 500),
                  ),
                ),
              ),
              const Positioned(right: -8, top: -10, child: _Sparkle(20)),
              const Positioned(right: -12, top: 18, child: _Sparkle(9)),
              const Positioned(left: -8, bottom: -12, child: _Sparkle(24)),
              const Positioned(left: 14, bottom: -6, child: _Sparkle(8)),
            ]),
          ]),
        ),
      ),
      Positioned(
        left: 30,
        right: 30,
        bottom: 0,
        child: GlowButton('Cast your wish', glyph: GlyphKind.spark, onPressed: _submit),
      ),
    ]);
  }
}

class _Sparkle extends StatelessWidget {
  final double size;
  const _Sparkle(this.size);

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Glyph(GlyphKind.spark, size: size, color: Colors.white, filled: true),
      );
}

class _FilterChips extends StatelessWidget {
  final AppState state;
  const _FilterChips({required this.state});

  @override
  Widget build(BuildContext context) {
    final tabs = <(WishCategory?, String)>[
      (null, 'All'),
      for (final c in WishCategory.values) (c, c.label),
    ];
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(MW.gutter, 4, MW.gutter, 10),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (cat, label) = tabs[i];
          final selected = state.filter == cat;
          return Semantics(
            button: true,
            selected: selected,
            label: label,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.selection();
                state.setFilter(cat);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: selected ? MW.glow : null,
                  color: selected ? null : MW.glass,
                  border: Border.all(
                    color: selected ? Colors.white.withValues(alpha: 0.55) : const Color(0x40FFFFFF),
                  ),
                ),
                child: Text(label, style: MW.ui(13.5, color: Colors.white, weight: selected ? 900 : 700)),
              ),
            ),
          );
        },
      ),
    );
  }
}
