import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../state/admin_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/settings_kit.dart';
import '../../widgets/ui.dart';
import 'admin_kit.dart';

/// Switches and messages that change the live app for everyone, within seconds
/// and without a new release. Leaving with unsaved changes asks first.
class ControlsScreen extends StatefulWidget {
  const ControlsScreen({super.key});

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends State<ControlsScreen> {
  late final AdminBackend _tools;
  late final TextEditingController _banner;
  late final TextEditingController _terms;
  late AppConfig _saved;
  late bool _paused;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _tools = state.adminTools!;
    _saved = state.config;
    _paused = _saved.wishingPaused;
    _banner = TextEditingController(text: _saved.banner)..addListener(_changed);
    _terms = TextEditingController(text: _saved.blockedTerms.join(', '))..addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _banner.dispose();
    _terms.dispose();
    super.dispose();
  }

  AppConfig get _draft => AppConfig(
        wishingPaused: _paused,
        banner: _banner.text.trim(),
        blockedTerms: AppConfig.parseTerms(_terms.text),
      );

  bool get _dirty => _draft != _saved;

  Future<void> _save() async {
    final draft = _draft;
    // Pausing stops every member at once, so make that a deliberate choice.
    if (draft.wishingPaused && !_saved.wishingPaused) {
      final yes = await confirmDialog(
        context,
        title: 'Pause new wishes?',
        body: 'Nobody can share a new wish until you turn this off. Luck, Daily Sparks and the '
            'Proof Vault keep working.',
        confirm: 'Pause',
      );
      if (!yes || !mounted) return;
    }
    setState(() => _saving = true);
    final ok = await runAdmin(context, () => _tools.saveConfig(draft), done: 'Saved. Phones pick it up within seconds.');
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _saved = draft;
        // Show the cleaned-up list (lower-cased, de-duplicated) that was saved.
        _terms.text = draft.blockedTerms.join(', ');
      }
    });
  }

  Future<void> _confirmLeave() async {
    final leave = await confirmDialog(
      context,
      title: 'Discard your changes?',
      body: 'You changed some controls but have not saved them. If you leave now they are lost.',
      confirm: 'Discard',
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final changedAt = context.select<AppState, DateTime?>((s) => s.config.updatedAt);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: AdminPage(
        title: 'Controls',
        area: AdminArea.controls,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 40),
          children: [
            SettingsSection(
              label: 'Sharing',
              footer: 'While paused, nobody can share a new wish. People can still send luck, and Daily Sparks '
                  'and proof stay private as always.',
              children: [
                SettingsRow(
                  glyph: GlyphKind.lock,
                  title: 'Pause new wishes',
                  subtitle: _paused ? 'On: sharing is paused' : 'Off: sharing is open',
                  tint: _paused ? adminDanger : MW.violet,
                  trailing: GlowSwitch(
                    key: const ValueKey('switch-pause'),
                    value: _paused,
                    semanticLabel: 'Pause new wishes',
                    onChanged: (v) => setState(() => _paused = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            const SectionHeading('Banner'),
            const SizedBox(height: 6),
            Text('A short note at the top of the Well. Leave it empty to show nothing.',
                style: MW.ui(13, color: MW.textDim, height: 1.45)),
            const SizedBox(height: 12),
            AdminField(
              key: const ValueKey('field-banner'),
              controller: _banner,
              hint: 'For example: Our monthly gratitude circle is Friday.',
              minLines: 2,
              maxLines: 4,
              maxLength: AppConfig.bannerMax,
            ),
            const SizedBox(height: 10),
            const Caps('How it looks in the app'),
            const SizedBox(height: 8),
            _BannerPreview(paused: _paused, banner: _banner.text.trim()),
            const SizedBox(height: 26),
            const SectionHeading('Blocked words'),
            const SizedBox(height: 6),
            Text(
              'Separate with commas or new lines. A wish containing one of these as a whole word or phrase '
              'is refused on the phone, and hidden automatically if it gets through (it then appears in '
              'Reports). "ass" never catches "class".',
              style: MW.ui(13, color: MW.textDim, height: 1.45),
            ),
            const SizedBox(height: 12),
            AdminField(
              key: const ValueKey('field-terms'),
              controller: _terms,
              hint: 'spam, buy now, giveaway',
              minLines: 3,
              maxLines: 6,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text('${AppConfig.parseTerms(_terms.text).length} of ${AppConfig.termsMax} terms',
                    style: MW.ui(12, color: MW.textFaint, weight: 700)),
              ),
            ),
            const SizedBox(height: 22),
            GlowButton('Save changes', isLoading: _saving, onPressed: _dirty ? _save : null),
            if (_dirty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Center(
                  child: Text('You have unsaved changes.', style: MW.ui(12.5, color: MW.goldBright, weight: 700)),
                ),
              ),
            if (changedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Center(
                  child: Text('Last changed ${whenLabel(changedAt)}.',
                      style: MW.ui(12, color: MW.textFaint, weight: 700)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The notice exactly as members see it at the top of the Well, so an admin
/// can judge the wording before saving.
class _BannerPreview extends StatelessWidget {
  final bool paused;
  final String banner;
  const _BannerPreview({required this.paused, required this.banner});

  @override
  Widget build(BuildContext context) {
    if (!paused && banner.isEmpty) {
      return Text('Nothing shows at the top of the Well.', style: MW.ui(13, color: MW.textFaint, height: 1.4));
    }
    final headline = paused ? 'New wishes are paused for a little while. You can still send luck.' : banner;
    return Semantics(
      container: true,
      label: 'Preview: $headline${paused && banner.isNotEmpty ? '. $banner' : ''}',
      excludeSemantics: true,
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
              Text(headline, style: MW.ui(14.5, color: MW.text, weight: 700, height: 1.4)),
              if (paused && banner.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(banner, style: MW.ui(13.5, color: MW.textDim, height: 1.4)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
