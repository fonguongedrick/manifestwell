import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/wish.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/haptics.dart';
import '../utils/step_suggester.dart';
import 'glyphs.dart';
import 'ui.dart';

/// Opens the small-steps sheet for one of the person's wishes. [onRevisit] runs
/// (after the sheet closes) when they choose to revisit the wish once every
/// step is done.
Future<void> showStepsSheet(BuildContext context, String wishId, {required VoidCallback onRevisit}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _StepsSheet(wishId: wishId, onRevisit: onRevisit),
  );
}

class _StepsSheet extends StatefulWidget {
  final String wishId;
  final VoidCallback onRevisit;
  const _StepsSheet({required this.wishId, required this.onRevisit});

  @override
  State<_StepsSheet> createState() => _StepsSheetState();
}

class _StepsSheetState extends State<_StepsSheet> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _addTyped() async {
    final text = _field.text;
    if (text.trim().isEmpty) return;
    _field.clear();
    await context.read<AppState>().addSteps(widget.wishId, [text]);
  }

  Future<void> _toggle(Wish wish, WishStep step) async {
    final state = context.read<AppState>();
    final finishing = !step.done && wish.progress.done == wish.progress.total - 1;
    await state.toggleStep(wish.id, step.id);
    // A little more weight for the step that completes the set.
    if (finishing) {
      Haptics.medium();
    } else {
      Haptics.selection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final wish = state.myWish(widget.wishId);
    // The wish was resolved or removed while the sheet was open.
    if (wish == null) return const SizedBox.shrink();

    final p = wish.progress;
    final allDone = p.total > 0 && p.done == p.total;
    final ideas = StepSuggester.suggest(wish, max: 8)
        .where((s) => !wish.steps.any((e) => e.text.toLowerCase() == s.toLowerCase()))
        .take(4)
        .toList();
    final full = wish.steps.length >= WishStep.maxPerWish;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x59FFFFFF))),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xE6372A80), Color(0xF21A1146)],
            ),
          ),
          padding: EdgeInsets.fromLTRB(MW.gutter, 12, MW.gutter, MediaQuery.viewInsetsOf(context).bottom + 20),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeading('Small steps', glyph: GlyphKind.spark),
                const SizedBox(height: 12),
                Text(wish.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: MW.voice(18)),
                const SizedBox(height: 16),
                if (p.total > 0) ...[
                  _Progress(done: p.done, total: p.total),
                  const SizedBox(height: 8),
                ] else
                  Text(
                    'A big wish moves when the next step is small. Break this one into pieces you could do in '
                    'about fifteen minutes each.',
                    style: MW.ui(14.5, color: MW.textDim, height: 1.5),
                  ),
                if (p.total == 0) ...[
                  const SizedBox(height: 18),
                  GlowButton(
                    'Break it down for me',
                    glyph: GlyphKind.spark,
                    onPressed: () async {
                      await state.addSteps(wish.id, StepSuggester.starter(wish));
                      Haptics.light();
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'These are starting points, not rules. Change, add or remove any of them.',
                    style: MW.ui(12.5, color: MW.textFaint, height: 1.4),
                  ),
                ],
                for (final step in wish.steps) _StepRow(step: step, onToggle: () => _toggle(wish, step), onRemove: () {
                  state.removeStep(wish.id, step.id);
                }),
                if (allDone) ...[
                  const SizedBox(height: 16),
                  GlassCard(
                    radius: 20,
                    blur: 8,
                    borderColor: MW.gold.withValues(alpha: 0.6),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Every step is done.', style: MW.ui(16, color: MW.goldBright, weight: 800)),
                      const SizedBox(height: 4),
                      Text('How is the wish itself? Take a moment to revisit it.',
                          style: MW.ui(14, color: MW.textDim, height: 1.4)),
                      const SizedBox(height: 12),
                      GlowButton(
                        'Revisit this wish',
                        compact: true,
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onRevisit();
                        },
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                if (full)
                  Text('That is plenty for one wish. Finish a few before adding more.',
                      style: MW.ui(13.5, color: MW.textDim, height: 1.4))
                else
                  _AddRow(controller: _field, onAdd: _addTyped),
                if (!full && p.total > 0 && ideas.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Caps('Ideas'),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final idea in ideas)
                      _IdeaChip(text: idea, onTap: () => state.addSteps(wish.id, [idea])),
                  ]),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  final int done;
  final int total;
  const _Progress({required this.done, required this.total});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$done of $total steps done',
        excludeSemantics: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$done of $total done', style: MW.ui(13.5, color: MW.goldBright, weight: 800)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(children: [
              Container(height: 7, color: const Color(0x26FFFFFF)),
              FractionallySizedBox(
                widthFactor: (done / total).clamp(0.0, 1.0),
                child: Container(height: 7, decoration: const BoxDecoration(gradient: MW.glow)),
              ),
            ]),
          ),
        ]),
      );
}

class _StepRow extends StatelessWidget {
  final WishStep step;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  const _StepRow({required this.step, required this.onToggle, required this.onRemove});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Semantics(
            checked: step.done,
            label: step.text,
            excludeSemantics: true,
            onTap: onToggle,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: step.done ? MW.glow : null,
                      border: Border.all(color: step.done ? Colors.white54 : const Color(0x66FFFFFF), width: 1.5),
                    ),
                    child: step.done ? const Glyph(GlyphKind.check, size: 15, color: Colors.white, stroke: 2.2) : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      step.text,
                      style: MW.voice(16, color: step.done ? MW.textFaint : MW.text, weight: 600).copyWith(
                        decoration: step.done ? TextDecoration.lineThrough : null,
                        decorationColor: MW.textFaint,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: 'Remove step: ${step.text}',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Center(child: Glyph(GlyphKind.close, size: 16, color: MW.textFaint, stroke: 1.6)),
            ),
          ),
        ),
      ]);
}

class _AddRow extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onAdd;
  const _AddRow({required this.controller, required this.onAdd});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 2, 6, 2),
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: MW.violet.withValues(alpha: 0.6), width: 1.2),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              inputFormatters: [LengthLimitingTextInputFormatter(WishStep.maxLength)],
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onAdd(),
              cursorColor: MW.lilac,
              style: MW.voice(16),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Add a small step',
                hintStyle: MW.ui(15.5, color: MW.textFaint),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Add step',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAdd,
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: MW.glow),
                child: const Center(child: Glyph(GlyphKind.starPlus, size: 20, color: Colors.white, stroke: 1.8)),
              ),
            ),
          ),
        ]),
      );
}

class _IdeaChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _IdeaChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Add idea: $text',
        excludeSemantics: true,
        child: Pressable(
          onPressed: onTap,
          builder: (_) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: MW.glass,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x40FFFFFF)),
            ),
            child: Text('+  $text', style: MW.ui(13.5, color: MW.textDim, weight: 700, height: 1.3)),
          ),
        ),
      );
}
