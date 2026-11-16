import 'package:flutter_test/flutter_test.dart';
import 'package:manifestwell/models/wish.dart';
import 'package:manifestwell/state/app_state.dart';
import 'package:manifestwell/utils/moderation.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _fresh([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return AppState.load(now: () => DateTime(2026, 10, 27, 12));
}

void main() {
  group('Moderation', () {
    test('accepts a positive wish', () {
      expect(Moderation.check('Hoping my interview goes great ✨'), isNull);
    });
    test('rejects empty, too long, profanity, links and phone numbers', () {
      expect(Moderation.check('   '), isNotNull);
      expect(Moderation.check('a' * (Moderation.maxLength + 1)), isNotNull);
      expect(Moderation.check('what the fuck'), isNotNull);
      expect(Moderation.check('visit www.spam.io now'), isNotNull);
      expect(Moderation.check('call me 555-123-4567'), isNotNull);
    });
  });

  group('AppState', () {
    test('Well is pre-seeded and anonymous', () async {
      final s = await _fresh();
      expect(s.feed.length, greaterThanOrEqualTo(20));
      expect(s.feed.every((w) => w.isSeed && !w.isMine), isTrue);
    });

    test('free tier allows one active big wish; sparks do not count', () async {
      final s = await _fresh();
      expect(await s.cast('first', WishKind.big, WishCategory.career), isNotNull);
      expect(s.canCastBigWish, isFalse);
      expect(await s.cast('second', WishKind.big, WishCategory.love), isNull);
      expect(await s.cast('free coffee', WishKind.spark, WishCategory.daily), isNotNull);
      expect(s.activeWishes.length, 1);
    });

    test('resolving a wish frees the slot and files proof', () async {
      final s = await _fresh();
      final w = (await s.cast('first', WishKind.big, WishCategory.career))!;
      await s.resolve(w.id, WishStatus.granted, note: 'Signed!');
      expect(s.canCastBigWish, isTrue);
      expect(s.proof.single.note, 'Signed!');
      expect(s.feed.any((x) => x.id == w.id), isFalse);
    });

    test('letting go archives without adding proof', () async {
      final s = await _fresh();
      final w = (await s.cast('first', WishKind.big, WishCategory.career))!;
      await s.resolve(w.id, WishStatus.letGo);
      expect(s.proof, isEmpty);
      expect(s.activeWishes, isEmpty);
    });

    test('a spark lands in the vault immediately', () async {
      final s = await _fresh();
      await s.cast('free coffee', WishKind.spark, WishCategory.daily);
      expect(s.proof.length, 1);
      expect(s.feed.any((w) => w.isMine), isFalse);
    });

    test('luck sends once per wish and unlocks the golden orb at five', () async {
      final s = await _fresh();
      final ids = s.feed.take(5).map((w) => w.id).toList();
      final before = s.feed.first.luck;
      expect(await s.sendLuck(ids.first), isTrue);
      expect(await s.sendLuck(ids.first), isFalse);
      expect(s.feed.firstWhere((w) => w.id == ids.first).luck, before + 1);
      expect(s.goldenOrbUnlocked, isFalse);
      for (final id in ids.skip(1)) {
        await s.sendLuck(id);
      }
      expect(s.goldenOrbUnlocked, isTrue);
    });

    test('cannot send luck to your own wish', () async {
      final s = await _fresh();
      final w = (await s.cast('mine', WishKind.big, WishCategory.career))!;
      expect(await s.sendLuck(w.id), isFalse);
    });

    test('state survives a restart', () async {
      final s = await _fresh();
      await s.cast('persist me', WishKind.big, WishCategory.travel);
      await s.completeOnboarding();
      final reloaded = await AppState.load(now: () => DateTime(2026, 10, 27, 12));
      expect(reloaded.onboarded, isTrue);
      expect(reloaded.activeWishes.single.text, 'persist me');
    });

    test('golden orb resets on a new day', () async {
      final s = await _fresh();
      for (final w in s.feed.take(5)) {
        await s.sendLuck(w.id);
      }
      final tomorrow = await AppState.load(now: () => DateTime(2026, 10, 28, 9));
      expect(tomorrow.goldenOrbUnlocked, isFalse);
    });
  });
}
