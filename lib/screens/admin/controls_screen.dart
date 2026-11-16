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
/// and without a new release.
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

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Controls',
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
          ],
        ),
      );
}
