import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/wish.dart';

/// A wish document as the app's [Wish]. Shared by the member and admin
/// backends so both read the same shape. Callers skip documents whose
/// createdAt is still null (our own pending write).
Wish wishFromDoc(String id, Map<String, dynamic> m) => Wish(
      id: id,
      text: m['text'] as String,
      kind: WishKind.values.byName(m['kind'] as String),
      category: WishCategory.values.byName(m['category'] as String),
      createdAt: (m['createdAt'] as Timestamp).toDate(),
      luck: (m['luck'] as num?)?.toInt() ?? 0,
    );

DateTime? dateOf(Object? timestamp) => timestamp is Timestamp ? timestamp.toDate() : null;
