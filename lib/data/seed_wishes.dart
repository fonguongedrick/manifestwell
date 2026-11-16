import '../models/wish.dart';

/// Evergreen, anonymous seed wishes so the Well never looks empty on day one.
/// No dates or names, so they never feel stale. Flagged isSeed so they can be
/// phased out as real volume grows.
List<Wish> buildSeedWishes(DateTime now) {
  const rows = <(String, WishCategory, WishKind, int)>[
    ('Hoping my client approves the final design proposal today ✨', WishCategory.career, WishKind.big, 184),
    ('Manifesting a successful product launch with zero bugs this week.', WishCategory.career, WishKind.big, 92),
    ('Ready to crush this afternoon\'s job interview and get an offer.', WishCategory.career, WishKind.big, 240),
    ('Calling in a raise I know I\'ve earned.', WishCategory.career, WishKind.big, 131),
    ('Hoping for my dream apartment approval this week 🏡✨', WishCategory.home, WishKind.big, 142),
    ('Manifesting a peaceful roommate and a smooth moving day.', WishCategory.home, WishKind.big, 67),
    ('One day soon, keys to a home that is entirely mine.', WishCategory.home, WishKind.big, 173),
    ('Sending out good energy to meet someone who matches my ambition and vibe.', WishCategory.love, WishKind.big, 115),
    ('Hoping my sister\'s wedding is full of pure joy and beautiful memories.', WishCategory.love, WishKind.big, 203),
    ('Wishing for a conversation that finally mends things with my dad.', WishCategory.love, WishKind.big, 158),
    ('Asking my body for one more strong, steady month of healing.', WishCategory.health, WishKind.big, 109),
    ('Manifesting a clean bill of health at tomorrow\'s checkup.', WishCategory.health, WishKind.big, 146),
    ('A solo trip somewhere with an ocean and no alarm clock.', WishCategory.travel, WishKind.big, 88),
    ('Hoping my flight is smooth and my bags arrive with me ✈️', WishCategory.travel, WishKind.big, 54),
    ('Manifesting a smooth morning commute and a productive flow state all day.', WishCategory.daily, WishKind.big, 45),
    ('Hoping my morning matcha tastes amazing and I find a great parking spot.', WishCategory.daily, WishKind.big, 31),
    ('Found a twenty-dollar bill in my old winter coat today! 🧥✨', WishCategory.daily, WishKind.spark, 118),
    ('My morning iced coffee was free because the barista was sweet.', WishCategory.daily, WishKind.spark, 84),
    ('Crushed an unexpected 2 PM meeting with zero prep.', WishCategory.daily, WishKind.spark, 156),
    ('A stranger held the door and then complimented my jacket 🌸', WishCategory.daily, WishKind.spark, 63),
    ('The rain stopped exactly when I stepped outside.', WishCategory.daily, WishKind.spark, 97),
    ('My favorite song came on the second I got in the car.', WishCategory.daily, WishKind.spark, 72),
    ('Got the last slice of the good cake at the bakery 🍰', WishCategory.daily, WishKind.spark, 41),
    ('An old friend texted me out of nowhere today 🤝', WishCategory.daily, WishKind.spark, 125),
    ('Every light was green on the way to work.', WishCategory.daily, WishKind.spark, 58),
  ];
  return [
    for (var i = 0; i < rows.length; i++)
      Wish(
        id: 'seed_$i',
        text: rows[i].$1,
        category: rows[i].$2,
        kind: rows[i].$3,
        luck: rows[i].$4,
        // Spread across the last day so the feed reads as live.
        createdAt: now.subtract(Duration(minutes: 7 + i * 53)),
        isSeed: true,
      ),
  ];
}
