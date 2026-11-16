import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin.dart';
import '../../models/moderation.dart';
import '../../state/admin_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/haptics.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/ui.dart';
import 'admin_kit.dart';

enum _Tab { reports, wishes }

enum _Filter { all, reported, hidden }

enum _Sort {
  newest('Newest'),
  mostReported('Most reported'),
  mostLuck('Most luck');

  final String label;
  const _Sort(this.label);
}

/// One thing to review: a wish (if it is still there) and the reports on it.
class _Item {
  final String id;
  final ModWish? wish;
  final List<WishReport> reports;
  const _Item(this.id, this.wish, this.reports);

  DateTime? get latestReport =>
      reports.map((r) => r.at).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
}

/// The moderation queue: reported wishes first, then every wish in the Well.
/// Search, sort, select several at once, and every removal or block asks why,
/// so it can be explained later from the activity log.
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  static const _pageSize = 200;
  static const _maxLimit = 1000;

  _Tab _tab = _Tab.reports;
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.newest;
  String _query = '';
  bool _selecting = false;
  final _selected = <String>{};
  int _limit = _pageSize;

  final _search = TextEditingController();
  late final AdminBackend _tools;
  late Stream<List<ModWish>> _wishes;
  late final Stream<List<WishReport>> _reports;
  late final Stream<List<BlockedPerson>> _blocked;

  @override
  void initState() {
    super.initState();
    _tools = context.read<AppState>().adminTools!;
    // Each stream is subscribed to once, however the tab or filter changes.
    _wishes = _tools.watchAllWishes(limit: _limit);
    _reports = _tools.watchReports();
    _blocked = _tools.watchBlocked();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _loadMore() {
    setState(() {
      _limit = (_limit + _pageSize).clamp(0, _maxLimit);
      _wishes = _tools.watchAllWishes(limit: _limit);
    });
  }

  void _toggleSelecting() {
    setState(() {
      _selecting = !_selecting;
      _selected.clear();
    });
  }

  // ---- Which items to show ------------------------------------------------------

  List<_Item> _items(List<ModWish> wishes, List<WishReport> reports) {
    final byWish = <String, List<WishReport>>{};
    for (final r in reports) {
      byWish.putIfAbsent(r.wishId, () => []).add(r);
    }
    final byId = {for (final w in wishes) w.wish.id: w};

    final List<_Item> items;
    if (_tab == _Tab.reports) {
      items = [for (final e in byWish.entries) _Item(e.key, byId[e.key], e.value)];
    } else {
      items = [
        for (final w in wishes)
          if (switch (_filter) {
            _Filter.all => true,
            _Filter.reported => byWish.containsKey(w.wish.id),
            _Filter.hidden => w.hidden,
          })
            _Item(w.wish.id, w, byWish[w.wish.id] ?? const []),
      ];
    }

    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? items
        : [
            for (final i in items)
              if (_matches(i, q)) i,
          ];

    int newest(_Item a, _Item b) {
      final at = _tab == _Tab.reports ? a.latestReport : a.wish?.wish.createdAt;
      final bt = _tab == _Tab.reports ? b.latestReport : b.wish?.wish.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    }

    shown.sort(switch (_sort) {
      _Sort.newest => newest,
      _Sort.mostReported => (a, b) {
          final c = b.reports.length.compareTo(a.reports.length);
          return c != 0 ? c : newest(a, b);
        },
      _Sort.mostLuck => (a, b) {
          final c = (b.wish?.wish.luck ?? 0).compareTo(a.wish?.wish.luck ?? 0);
          return c != 0 ? c : newest(a, b);
        },
    });
    return shown;
  }

  bool _matches(_Item i, String q) {
    final w = i.wish;
    if (w == null) return false;
    return w.wish.text.toLowerCase().contains(q) ||
        w.wish.category.label.toLowerCase().contains(q) ||
        (w.authorUid?.toLowerCase().startsWith(q) ?? false) ||
        i.reports.any((r) => r.reason.toLowerCase().contains(q));
  }

  // ---- Actions ----------------------------------------------------------------

  void _toast(String text, {VoidCallback? undo}) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 6),
      action: undo == null ? null : SnackBarAction(label: 'Undo', onPressed: undo),
    ));
  }

  Future<void> _hide(List<String> ids, bool hidden) async {
    final ok = await runAdmin(
      context,
      () => ids.length == 1 ? _tools.setHidden(ids.single, hidden) : _tools.setHiddenMany(ids, hidden),
    );
    if (!ok || !mounted) return;
    Haptics.light();
    final n = ids.length;
    _toast(
      hidden ? (n == 1 ? 'Hidden.' : '$n wishes hidden.') : (n == 1 ? 'Restored.' : '$n wishes restored.'),
      undo: () => ids.length == 1 ? _tools.setHidden(ids.single, !hidden) : _tools.setHiddenMany(ids, !hidden),
    );
    if (_selecting) setState(_selected.clear);
  }

  Future<void> _remove(List<String> ids) async {
    final many = ids.length > 1;
    final picked = await showReasonSheet(
      context,
      title: many ? 'Remove ${ids.length} wishes?' : 'Remove this wish?',
      message: 'Deleted for everyone, together with the reports on ${many ? 'them' : 'it'}. This cannot be '
          'undone. Say why, so it is on record.',
      confirmLabel: many ? 'Remove ${ids.length} wishes' : 'Remove wish',
    );
    if (picked == null || !mounted) return;
    final ok = await runAdmin(
      context,
      () => many
          ? _tools.removeWishes(ids, reason: picked.reason, note: picked.note)
          : _tools.removeWish(ids.single, reason: picked.reason, note: picked.note),
      done: many ? '${ids.length} wishes removed.' : 'Removed.',
    );
    if (ok && mounted) setState(_selected.clear);
  }

  Future<void> _block(ModWish w) async {
    final picked = await showReasonSheet(
      context,
      title: 'Block this person?',
      message: 'They can no longer share wishes or send luck, and everything they have shared is hidden from the '
          'Well. You can unblock them later in People.',
      confirmLabel: 'Block person',
    );
    if (picked == null || !mounted) return;
    await runAdmin(
      context,
      () => _tools.block(w.authorUid!, reason: picked.reason, note: picked.note),
      done: 'Blocked.',
    );
  }

  Future<void> _dismiss(List<String> wishIds) async {
    final ok = await runAdmin(context, () => _tools.dismissReportsFor(wishIds), done: 'Reports dismissed.');
    if (ok && mounted) setState(_selected.clear);
  }

  Future<void> _pickSort() async {
    final picked = await showModalBottomSheet<_Sort>(
      context: context,
      backgroundColor: MW.inkDeep,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SORT BY', style: MW.display(21)),
            const SizedBox(height: 10),
            for (final s in _Sort.values)
              Semantics(
                button: true,
                selected: s == _sort,
                label: s.label,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(ctx).pop(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    child: Row(children: [
                      Expanded(
                        child: Text(s.label,
                            style: MW.ui(16, color: s == _sort ? MW.goldBright : MW.text, weight: 700)),
                      ),
                      if (s == _sort) const Glyph(GlyphKind.check, size: 18, color: MW.goldBright, stroke: 2),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  // ---- Build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Moderation',
        area: AdminArea.moderation,
        actions: [QuietLink(_selecting ? 'Done' : 'Select', color: MW.lilac, onPressed: _toggleSelecting)],
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MW.gutter),
            child: SlidingSegment<_Tab>(
              options: const [(_Tab.reports, 'Reports'), (_Tab.wishes, 'All wishes')],
              value: _tab,
              onChanged: (t) => setState(() {
                _tab = t;
                _selected.clear();
              }),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MW.gutter),
            child: Row(children: [
              Expanded(
                child: AdminSearchField(
                  controller: _search,
                  hint: 'Search wishes, people, reasons',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'Sort: ${_sort.label}',
                excludeSemantics: true,
                child: Pressable(
                  onPressed: _pickSort,
                  builder: (_) => Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: MW.glass,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0x40FFFFFF)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Glyph(GlyphKind.sliders, size: 17, color: MW.lilac, stroke: 1.7),
                      const SizedBox(width: 8),
                      Text(_sort.label, style: MW.ui(13.5, color: MW.text, weight: 800)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
          if (_tab == _Tab.wishes) ...[
            const SizedBox(height: 10),
            FilterPills<_Filter>(
              options: const [(_Filter.all, 'All'), (_Filter.reported, 'Reported'), (_Filter.hidden, 'Hidden')],
              value: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: LiveView3<List<ModWish>, List<WishReport>, List<BlockedPerson>>(
              a: _wishes,
              b: _reports,
              c: _blocked,
              builder: (context, wishes, reports, blocked) {
                final blockedIds = {for (final b in blocked) b.uid};
                final items = _items(wishes, reports);
                final canLoadMore = _tab == _Tab.wishes && wishes.length >= _limit && _limit < _maxLimit;
                return Column(children: [
                  Expanded(
                    child: items.isEmpty
                        ? AdminMessage(_emptyText)
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 24),
                            children: [
                              for (final item in items)
                                _ModCard(
                                  key: ValueKey('card-${item.id}'),
                                  item: item,
                                  blocked: blockedIds,
                                  selecting: _selecting,
                                  selected: _selected.contains(item.id),
                                  onToggle: () => setState(() {
                                    if (!_selected.add(item.id)) _selected.remove(item.id);
                                  }),
                                  onHide: _hide,
                                  onRemove: _remove,
                                  onBlock: _block,
                                  onDismiss: (id, reportIds) => runAdmin(
                                    context,
                                    () => _tools.dismissReports(id, reportIds),
                                    done: 'Reports dismissed.',
                                  ),
                                ),
                              if (canLoadMore)
                                Center(
                                  child: QuietLink('Load more wishes', color: MW.lilac, onPressed: _loadMore),
                                ),
                            ],
                          ),
                  ),
                  if (_selecting)
                    _BulkBar(
                      count: _selected.length,
                      total: items.length,
                      showDismiss: items.any((i) => _selected.contains(i.id) && i.reports.isNotEmpty),
                      onSelectAll: () => setState(() {
                        _selected
                          ..clear()
                          ..addAll(items.map((i) => i.id));
                      }),
                      onHide: () => _hide(_stillThere(items), true),
                      onRestore: () => _hide(_stillThere(items), false),
                      onRemove: () => _remove(_stillThere(items)),
                      onDismiss: () => _dismiss([
                        for (final i in items)
                          if (_selected.contains(i.id) && i.reports.isNotEmpty) i.id,
                      ]),
                    ),
                ]);
              },
            ),
          ),
        ]),
      );

  /// Selected ids whose wish still exists (a removed wish can't be hidden).
  List<String> _stillThere(List<_Item> items) => [
        for (final i in items)
          if (_selected.contains(i.id) && i.wish != null) i.id,
      ];

  String get _emptyText {
    if (_query.trim().isNotEmpty) return 'Nothing matches “${_query.trim()}”.';
    if (_tab == _Tab.reports) return 'Nothing reported. The Well is calm.';
    return switch (_filter) {
      _Filter.all => 'No wishes in the Well yet.',
      _Filter.reported => 'No reported wishes.',
      _Filter.hidden => 'Nothing is hidden.',
    };
  }
}

/// The bar that appears while selecting: how many are chosen, and what to do
/// with them.
class _BulkBar extends StatelessWidget {
  final int count;
  final int total;
  final bool showDismiss;
  final VoidCallback onSelectAll;
  final VoidCallback onHide;
  final VoidCallback onRestore;
  final VoidCallback onRemove;
  final VoidCallback onDismiss;
  const _BulkBar({
    required this.count,
    required this.total,
    required this.showDismiss,
    required this.onSelectAll,
    required this.onHide,
    required this.onRestore,
    required this.onRemove,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final any = count > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(MW.gutter, 4, MW.gutter, 10),
      child: GlassCard(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
        borderColor: MW.violet.withValues(alpha: 0.7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(any ? '$count selected' : 'Tap wishes to select them',
                  style: MW.ui(14.5, color: MW.text, weight: 800)),
            ),
            if (count < total) QuietLink('Select all $total', color: MW.lilac, onPressed: onSelectAll),
          ]),
          if (any)
            Wrap(children: [
              _BarAction('Hide', MW.lilac, onHide),
              _BarAction('Restore', MW.lilac, onRestore),
              _BarAction('Remove', adminDanger, onRemove),
              if (showDismiss) _BarAction('Dismiss', MW.textDim, onDismiss),
            ]),
        ]),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _BarAction(this.label, this.color, this.onPressed);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: IntrinsicWidth(child: QuietLink(label, color: color, onPressed: onPressed)),
      );
}

class _ModCard extends StatefulWidget {
  final _Item item;
  final Set<String> blocked;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;
  final Future<void> Function(List<String> ids, bool hidden) onHide;
  final Future<void> Function(List<String> ids) onRemove;
  final Future<void> Function(ModWish wish) onBlock;
  final Future<bool> Function(String wishId, List<String> reportIds) onDismiss;
  const _ModCard({
    super.key,
    required this.item,
    required this.blocked,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onHide,
    required this.onRemove,
    required this.onBlock,
    required this.onDismiss,
  });

  @override
  State<_ModCard> createState() => _ModCardState();
}

class _ModCardState extends State<_ModCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final w = item.wish;
    final reports = item.reports;
    final uid = w?.authorUid;
    final isBlocked = uid != null && widget.blocked.contains(uid);
    final selectable = widget.selecting && w != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Semantics(
        container: true,
        selected: widget.selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: selectable ? widget.onToggle : null,
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            borderColor: widget.selected ? MW.violet : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (w == null)
                Text('This wish was already removed.', style: MW.ui(15, color: MW.textFaint))
              else
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (widget.selecting) ...[
                    _Check(widget.selected),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(w.wish.text, style: MW.voice(17.5)),
                      const SizedBox(height: 8),
                      Text(
                        '${w.wish.category.label} · ${w.wish.luck} luck${w.hidden ? ' · Hidden' : ''}',
                        style: MW.ui(12.5, color: w.hidden ? MW.goldBright : MW.textFaint, weight: 700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${whenLabel(w.wish.createdAt)} · by ${shortId(uid)}${isBlocked ? ' · Blocked' : ''}',
                        style: MW.ui(12, color: MW.textFaint),
                      ),
                    ]),
                  ),
                ]),
              if (reports.isNotEmpty) ...[
                const SizedBox(height: 10),
                Semantics(
                  button: true,
                  expanded: _open,
                  label: '${reports.length} report${reports.length == 1 ? '' : 's'}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _open = !_open),
                    child: Row(children: [
                      Text('${reports.length} report${reports.length == 1 ? '' : 's'}',
                          style: MW.ui(13, color: adminDanger, weight: 800)),
                      const SizedBox(width: 6),
                      RotatedBox(quarterTurns: _open ? 3 : 1, child: const Glyph(GlyphKind.chevronRight, size: 16, color: adminDanger, stroke: 2)),
                    ]),
                  ),
                ),
                const SizedBox(height: 2),
                if (!_open)
                  Text(reports.map((r) => r.reason).where((r) => r.isNotEmpty).toSet().join(' · '),
                      style: MW.ui(13, color: MW.textDim))
                else
                  for (final r in reports)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Text(r.reason.isEmpty ? 'No reason given' : r.reason,
                              style: MW.ui(13, color: MW.textDim, height: 1.35)),
                        ),
                        const SizedBox(width: 10),
                        Text(r.at == null ? 'just now' : '${ageLabel(r.at!)} ago',
                            style: MW.ui(12, color: MW.textFaint, weight: 700)),
                      ]),
                    ),
              ],
              if (!widget.selecting) ...[
                const SizedBox(height: 4),
                Wrap(children: [
                  if (w != null)
                    _Act(w.hidden ? 'Restore' : 'Hide',
                        color: MW.lilac, onPressed: () => widget.onHide([item.id], !w.hidden)),
                  if (w != null) _Act('Remove', color: adminDanger, onPressed: () => widget.onRemove([item.id])),
                  if (w != null && uid != null && !isBlocked)
                    _Act('Block author', color: adminDanger, onPressed: () => widget.onBlock(w)),
                  if (reports.isNotEmpty)
                    _Act('Dismiss reports',
                        onPressed: () => widget.onDismiss(item.id, [for (final r in reports) r.id])),
                ]),
              ] else
                const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  final bool on;
  const _Check(this.on);

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 24,
        height: 24,
        margin: const EdgeInsets.only(top: 1),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: on ? MW.glow : null,
          border: Border.all(color: on ? Colors.white54 : const Color(0x66FFFFFF), width: 1.5),
        ),
        child: on ? const Glyph(GlyphKind.check, size: 14, color: Colors.white, stroke: 2.2) : null,
      );
}

/// A card action sized to its label, so several sit side by side. (A bare
/// QuietLink fills the width it is given and would stack one per line.)
class _Act extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _Act(this.label, {this.color = MW.textDim, required this.onPressed});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: IntrinsicWidth(child: QuietLink(label, color: color, onPressed: onPressed)),
      );
}
