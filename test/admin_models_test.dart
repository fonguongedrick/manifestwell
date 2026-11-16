import 'package:flutter_test/flutter_test.dart';
import 'package:manifestwell/models/admin.dart';
import 'package:manifestwell/utils/csv.dart';
import 'package:manifestwell/utils/moderation.dart';

void main() {
  group('AppConfig', () {
    test('a missing or half-written document falls back to harmless defaults', () {
      expect(AppConfig.fromMap(null), AppConfig.defaults);
      final odd = AppConfig.fromMap({'wishingPaused': 'yes', 'banner': 42, 'blockedTerms': 'spam'});
      expect(odd.wishingPaused, isFalse); // only a real true pauses anything
      expect(odd.banner, isEmpty);
      expect(odd.blockedTerms, isEmpty);
    });

    test('reads a good document', () {
      final c = AppConfig.fromMap({
        'wishingPaused': true,
        'banner': '  Friday circle  ',
        'blockedTerms': ['spam', '', 7, ' scam '],
      });
      expect(c.wishingPaused, isTrue);
      expect(c.banner, 'Friday circle');
      expect(c.blockedTerms, ['spam', 'scam']);
    });

    test('typed terms are cleaned: split, lower-cased, de-duplicated, short ones dropped', () {
      expect(AppConfig.parseTerms('Spam, buy now\nSPAM,  x ,scam,'), ['spam', 'buy now', 'scam']);
      expect(AppConfig.parseTerms(''), isEmpty);
      expect(AppConfig.parseTerms('a' * 41), isEmpty); // absurdly long
    });

    test('the list is capped at what the security rules allow', () {
      final many = List.generate(150, (i) => 'term$i').join(',');
      expect(AppConfig.parseTerms(many).length, AppConfig.termsMax);
    });

    test('equality sees every field', () {
      const a = AppConfig(wishingPaused: true, banner: 'x', blockedTerms: ['a']);
      expect(a, const AppConfig(wishingPaused: true, banner: 'x', blockedTerms: ['a']));
      expect(a == a.copyWith(banner: 'y'), isFalse);
      expect(a == a.copyWith(blockedTerms: ['b']), isFalse);
      expect(a == a.copyWith(wishingPaused: false), isFalse);
    });
  });

  group('Subscriptions', () {
    test('status ids map to what the admin reads, and unknown ones count as active', () {
      expect(SubscriptionStatus.fromId('expired'), SubscriptionStatus.expired);
      expect(SubscriptionStatus.fromId('cancelled'), SubscriptionStatus.cancelled);
      expect(SubscriptionStatus.fromId('billing_issue'), SubscriptionStatus.billingIssue);
      expect(SubscriptionStatus.fromId('active'), SubscriptionStatus.active);
      expect(SubscriptionStatus.fromId(null), SubscriptionStatus.active);
    });

    test('only an expired subscription has lost access', () {
      expect(SubscriptionStatus.expired.hasAccess, isFalse);
      for (final s in [SubscriptionStatus.active, SubscriptionStatus.cancelled, SubscriptionStatus.billingIssue]) {
        expect(s.hasAccess, isTrue, reason: s.name);
      }
    });

    test('says where a purchase came from, in whatever case RevenueCat sends the store', () {
      SubscriberDetail d({String? store, bool purchase = true}) =>
          SubscriberDetail(uid: 'u', email: '', purchaseActive: purchase, store: store);
      expect(d(store: 'APP_STORE').purchaseSource, 'Bought on the App Store');
      expect(d(store: 'app_store').purchaseSource, 'Bought on the App Store');
      expect(d(store: 'MAC_APP_STORE').purchaseSource, 'Bought on the App Store');
      expect(d(store: 'PLAY_STORE').purchaseSource, 'Bought on Google Play');
      expect(d(store: 'STRIPE').purchaseSource, 'Bought on the web');
      expect(d(store: 'something_new').purchaseSource, 'Bought in a store');
      expect(d(store: null).purchaseSource, isNull);
      expect(d(store: 'APP_STORE', purchase: false).purchaseSource, isNull);
    });

    test('a gift ends exactly when it says, or never for life', () {
      final now = DateTime(2026, 11, 10, 12);
      expect(PlusGrant(until: now.add(const Duration(seconds: 1))).isActive(now), isTrue);
      expect(PlusGrant(until: now).isActive(now), isFalse);
      expect(PlusGrant(until: now.subtract(const Duration(days: 1))).isActive(now), isFalse);
      expect(const PlusGrant(lifetime: true).isActive(now), isTrue);
      expect(const PlusGrant().isActive(now), isFalse);
    });

    test('with both a purchase and a gift, the later end date wins; a lifetime gift has none', () {
      final both = SubscriberDetail(
        uid: 'u',
        email: '',
        purchaseActive: true,
        purchaseExpiresAt: DateTime(2027, 3, 9),
        grantActive: true,
        grantExpiresAt: DateTime(2027, 1, 5),
      );
      expect(both.expiresAt, DateTime(2027, 3, 9));
      final life = SubscriberDetail(uid: 'u', email: '', grantActive: true, grantLifetime: true);
      expect(life.lifetime, isTrue);
      expect(life.expiresAt, isNull);
      const none = SubscriberDetail(uid: 'u', email: '');
      expect(none.active, isFalse);
      expect(none.expiresAt, isNull);
    });

    test('a list row has Plus by purchase or by an unexpired gift, and not otherwise', () {
      final now = DateTime(2026, 11, 10);
      SubscriberRecord r(SubscriptionStatus s, [PlusGrant? g]) => SubscriberRecord(uid: 'u', status: s, grant: g);
      expect(r(SubscriptionStatus.active).hasPlus(now), isTrue);
      expect(r(SubscriptionStatus.cancelled).hasPlus(now), isTrue);
      expect(r(SubscriptionStatus.expired).hasPlus(now), isFalse);
      expect(r(SubscriptionStatus.expired, const PlusGrant(lifetime: true)).hasPlus(now), isTrue);
      expect(r(SubscriptionStatus.expired, PlusGrant(until: DateTime(2026, 1, 1))).hasPlus(now), isFalse);
    });

    test('a member with no email is labelled, never blank', () {
      const guest = SubscriberRecord(uid: r'$RCAnonymousID:abc', guest: true, status: SubscriptionStatus.active);
      const noEmail = SubscriberRecord(uid: 'abcdef123456', status: SubscriptionStatus.active);
      expect(guest.label, 'Guest purchase');
      expect(noEmail.label, 'Person abcdef');
      expect(const AdminAccount(uid: 'abcdef123456', email: '').label, 'Admin abcdef');
    });

    test('every length the app offers is one the server knows', () {
      expect(GrantLength.values.map((l) => l.id), ['week', 'month', 'quarter', 'year', 'lifetime']);
    });
  });

  group('bucketByDay', () {
    final now = DateTime(2026, 11, 10, 15);

    test('gives one entry per day, oldest first, with zeros for quiet days', () {
      final days = bucketByDay([
        DateTime(2026, 11, 10, 9),
        DateTime(2026, 11, 10, 23, 59),
        DateTime(2026, 11, 8, 1),
      ], now: now, days: 4);
      expect(days.map((d) => d.day), [
        DateTime(2026, 11, 7),
        DateTime(2026, 11, 8),
        DateTime(2026, 11, 9),
        DateTime(2026, 11, 10),
      ]);
      expect(days.map((d) => d.count), [0, 1, 0, 2]);
    });

    test('ignores anything outside the window', () {
      final days = bucketByDay([DateTime(2026, 10, 1), DateTime(2026, 11, 11)], now: now, days: 3);
      expect(days.fold(0, (a, d) => a + d.count), 0);
    });

    test('stays one-entry-per-day across a daylight-saving change', () {
      // 2026-11-01 is when US clocks go back: that day has 25 hours.
      final days = bucketByDay([DateTime(2026, 11, 1, 12)], now: DateTime(2026, 11, 3, 10), days: 4);
      expect(days.map((d) => d.day.day), [31, 1, 2, 3]);
      expect(days.map((d) => d.count), [0, 1, 0, 0]);
    });
  });

  group('Csv', () {
    test('quotes commas, quotes and line breaks', () {
      expect(
        Csv.encode([
          ['a', 'b,c', 'say "hi"', 'two\nlines'],
        ]),
        'a,"b,c","say ""hi""","two\nlines"\r\n',
      );
    });

    test('a wish that looks like a formula cannot run as one in a spreadsheet', () {
      for (final evil in ['=HYPERLINK("http://x")', '+1+1', '-2+3', '@SUM(A1)']) {
        final cell = Csv.encode([
          [evil],
        ]);
        expect(cell.startsWith("'") || cell.startsWith('"\''), isTrue, reason: evil);
      }
    });

    test('numbers stay numbers, and negatives are not mistaken for formulas', () {
      expect(Csv.encode([[-5, 3, true, null]]), '-5,3,true,\r\n');
    });

    test('dates are written in UTC ISO form', () {
      expect(
        Csv.encode([
          [DateTime.utc(2026, 11, 10, 15, 30)],
        ]),
        '2026-11-10T15:30:00.000Z\r\n',
      );
    });
  });

  group('Moderation with the admin list', () {
    test('blocks a whole word, any case', () {
      expect(Moderation.check('Great SPAM here', extraBlocked: ['spam']), isNotNull);
      expect(Moderation.check('buy now please', extraBlocked: ['buy now']), isNotNull);
    });

    test('never trips inside a longer word', () {
      expect(Moderation.check('I passed my class', extraBlocked: ['ass']), isNull);
      expect(Moderation.check('Spamming is bad', extraBlocked: ['spam']), isNull);
    });

    test('punctuation does not hide a term', () {
      expect(Moderation.check('Scam!', extraBlocked: ['scam']), isNotNull);
      expect(Moderation.check('(scam)', extraBlocked: ['scam']), isNotNull);
    });

    test('regex characters in a term are literal', () {
      expect(Moderation.check('what is a.b today', extraBlocked: ['a.b']), isNotNull);
      expect(Moderation.check('axb today', extraBlocked: ['a.b']), isNull);
    });

    test('with no list a normal wish passes', () {
      expect(Moderation.check('A calm new home'), isNull);
    });
  });
}
