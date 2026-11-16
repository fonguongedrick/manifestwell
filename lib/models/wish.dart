enum WishKind { big, spark }

enum WishCategory {
  career('Career'),
  love('Love'),
  health('Health'),
  travel('Travel'),
  home('Home'),
  daily('Daily spark');

  final String label;
  const WishCategory(this.label);
}

/// The five honest outcomes when a user revisits a wish.
enum WishStatus {
  active('Active'),
  closer("I'm getting closer"),
  granted('It happened'),
  changed('My wish changed'),
  doorOpened('A different door opened'),
  letGo("I'm letting this go");

  final String label;
  const WishStatus(this.label);

  /// Still being held, so it counts toward the free-tier limit.
  bool get isOpen => this == active || this == closer;

  /// Resolved in a way that belongs in the Proof Vault timeline.
  bool get isProof => this == granted || this == doorOpened;
}

/// One small, doable step toward a wish: "Book the first appointment", not
/// "Get healthy". Kept on the wish, so it syncs with the account and stays
/// private (only a wish's text is ever shared in the Well).
class WishStep {
  /// A wish can hold this many steps; the cloud rules enforce the same cap.
  static const maxPerWish = 20;
  static const maxLength = 120;

  final String id;
  final String text;
  final DateTime? doneAt;
  const WishStep({required this.id, required this.text, this.doneAt});

  bool get done => doneAt != null;

  WishStep toggled(DateTime now) => WishStep(id: id, text: text, doneAt: done ? null : now);

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'doneAt': doneAt?.toIso8601String()};

  /// Null for anything unreadable, so one bad entry never loses the wish.
  static WishStep? tryParse(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final text = j['text'];
    if (id is! String || text is! String || text.trim().isEmpty) return null;
    final done = j['doneAt'];
    return WishStep(id: id, text: text, doneAt: done is String ? DateTime.tryParse(done) : null);
  }
}

class Wish {
  final String id;
  final String text;
  final WishKind kind;
  final WishCategory category;
  final DateTime createdAt;
  final int luck;
  final WishStatus status;
  final String? note;
  final String? tag;
  final DateTime? resolvedAt;

  /// When this wish last changed. Decides which copy wins when two devices
  /// have edited it. Older saved wishes have none, so fall back to creation.
  final DateTime? updatedAt;
  final bool isSeed;
  final bool isMine;

  /// The small steps this wish has been broken into, in order.
  final List<WishStep> steps;

  const Wish({
    required this.id,
    required this.text,
    required this.kind,
    required this.category,
    required this.createdAt,
    this.luck = 0,
    this.status = WishStatus.active,
    this.note,
    this.tag,
    this.resolvedAt,
    this.updatedAt,
    this.isSeed = false,
    this.isMine = false,
    this.steps = const [],
  });

  Wish copyWith({
    String? text,
    int? luck,
    WishStatus? status,
    String? note,
    DateTime? resolvedAt,
    DateTime? updatedAt,
    List<WishStep>? steps,
  }) =>
      Wish(
        id: id,
        text: text ?? this.text,
        kind: kind,
        category: category,
        createdAt: createdAt,
        luck: luck ?? this.luck,
        status: status ?? this.status,
        note: note ?? this.note,
        tag: tag,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isSeed: isSeed,
        isMine: isMine,
        steps: steps ?? this.steps,
      );

  /// Steps finished and steps in total, for a progress line.
  ({int done, int total}) get progress => (done: steps.where((s) => s.done).length, total: steps.length);

  DateTime get modified => updatedAt ?? createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'kind': kind.name,
        'category': category.name,
        'createdAt': createdAt.toIso8601String(),
        'luck': luck,
        'status': status.name,
        'note': note,
        'tag': tag,
        'resolvedAt': resolvedAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'steps': [for (final s in steps) s.toJson()],
      };

  factory Wish.fromJson(Map<String, dynamic> j) => Wish(
        id: j['id'] as String,
        text: j['text'] as String,
        kind: WishKind.values.byName(j['kind'] as String),
        category: WishCategory.values.byName(j['category'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
        luck: (j['luck'] as int?) ?? 0,
        status: WishStatus.values.byName(j['status'] as String),
        note: j['note'] as String?,
        tag: j['tag'] as String?,
        resolvedAt: j['resolvedAt'] == null
            ? null
            : DateTime.parse(j['resolvedAt'] as String),
        updatedAt: j['updatedAt'] == null ? null : DateTime.parse(j['updatedAt'] as String),
        isMine: true,
        steps: [
          if (j['steps'] is List)
            for (final raw in j['steps'] as List) ?WishStep.tryParse(raw),
        ],
      );
}
