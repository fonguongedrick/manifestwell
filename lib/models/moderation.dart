import 'wish.dart';

/// A wish as the admin sees it, including ones hidden from the public Well.
class ModWish {
  final Wish wish;
  final bool hidden;

  /// Who cast it. Anonymous to everyone else; an admin needs it to block them.
  final String? authorUid;
  const ModWish(this.wish, {required this.hidden, this.authorUid});
}

/// A member's flag on a wish, waiting for an admin.
class WishReport {
  final String id;
  final String wishId;
  final String reason;
  final DateTime? at;
  const WishReport({required this.id, required this.wishId, required this.reason, this.at});
}
