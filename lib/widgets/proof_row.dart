import 'package:flutter/material.dart';

import '../models/wish.dart';
import '../theme.dart';
import 'ui.dart';

/// A line of proof, as in the sample's GRANTS & GRATITUDE: the words and a
/// bracketed tag on the left, the luck it gathered on the right.
class ProofRow extends StatelessWidget {
  final Wish wish;
  final VoidCallback? onTap;
  const ProofRow({super.key, required this.wish, this.onTap});

  String get _tag {
    if (wish.kind == WishKind.spark) return wish.tag ?? 'Daily spark';
    return wish.status == WishStatus.doorOpened ? 'A different door' : 'Proof Vault';
  }

  @override
  Widget build(BuildContext context) {
    final when = wish.resolvedAt ?? wish.createdAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(MW.gutter, 0, MW.gutter, 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassCard(
          blur: 10,
          radius: 20,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(wish.text, style: MW.voice(17)),
                const SizedBox(height: 4),
                Text('[$_tag]  ·  ${_date(when)}', style: MW.ui(13, color: MW.textFaint, weight: 600)),
                if (wish.note != null) ...[
                  const SizedBox(height: 6),
                  Text(wish.note!, style: MW.ui(13.5, color: MW.textDim, height: 1.4)),
                ],
              ]),
            ),
            const SizedBox(width: 14),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${wish.luck}', style: MW.display(28, color: MW.goldBright)),
              const SizedBox(height: 2),
              const Caps('luck', size: 10, color: MW.textDim),
            ]),
          ]),
        ),
      ),
    );
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}';
}
