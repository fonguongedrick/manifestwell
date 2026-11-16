import '../models/wish.dart';

/// Suggests small first steps for a wish.
///
/// This is rule-based, not AI: it recognises what kind of wish it is from its
/// words (money, learning, fitness, travel...) and offers concrete steps that
/// each fit in about fifteen minutes. It works offline, never sends a wish
/// anywhere, and gives the same answer every time. People are meant to edit
/// the result: the point is to make starting feel small.
class StepSuggester {
  StepSuggester._();

  /// Steps for [wish], most useful first, never more than [max].
  static List<String> suggest(Wish wish, {int max = 5}) {
    final text = wish.text.toLowerCase();
    final out = <String>[];

    void add(Iterable<String> steps) {
      for (final s in steps) {
        if (out.length >= max) return;
        if (!out.contains(s)) out.add(s);
      }
    }

    // What the wish is about, from its own words. The first two topics that
    // match lead, so a wish that is about both saving and a house gets both.
    var matched = 0;
    for (final topic in _topics) {
      if (matched >= 2) break;
      if (topic.words.hasMatch(text)) {
        add(topic.steps);
        matched++;
      }
    }

    // Then the shape of the category, and finally steps that suit any wish.
    add(_byCategory[wish.category] ?? const []);
    add(_anyWish);
    return out;
  }

  /// Steps for a wish nobody has broken down yet, as one tap.
  static List<String> starter(Wish wish) => suggest(wish, max: 5);

  static final _topics = <_Topic>[
    _Topic(
      RegExp(r'\b(sav(e|ing|ings)|money|debt|pay off|afford|invest|income|budget|rich|wealth|salary|raise)\b'),
      const [
        'Write down the exact amount you need and by when',
        'Open a separate savings pot just for this',
        'Set up a small automatic transfer every payday',
        'List one expense you can cut this month',
      ],
    ),
    _Topic(
      RegExp(r'\b(learn|study|exam|degree|course|certificate|certification|graduate|school|college|language|fluent|license|licence)\b'),
      const [
        'Choose one course, book or teacher to start with',
        'Block three 25-minute study sessions this week',
        'Find out the next exam or deadline date',
        'Tell one person what you are studying',
      ],
    ),
    _Topic(
      RegExp(r'\b(run|running|marathon|weight|fit|fitness|gym|workout|exercise|strong|healthy|health|sleep|diet|eat|walk|yoga)\b'),
      const [
        'Book or schedule your first session',
        'Lay out your kit the night before',
        'Plan three short workouts this week',
        'Drink water and note how you feel after the first one',
      ],
    ),
    _Topic(
      RegExp(r'\b(travel|trip|visit|flight|abroad|holiday|vacation|explore|journey|tour)\b'),
      const [
        'Pick the dates or the month you would go',
        'Set a rough budget for the whole trip',
        'Check your passport and any visa you need',
        'Save three places you want to see',
      ],
    ),
    _Topic(
      RegExp(r'\b(house|home|apartment|flat|move|moving|rent|mortgage|room|garden|decorate|furnish)\b'),
      const [
        'List your must-haves and your deal-breakers',
        'Work out your monthly budget for it',
        'Spend 15 minutes browsing options',
        'Contact one agent, landlord or builder',
      ],
    ),
    _Topic(
      RegExp(r'\b(job|promotion|promoted|interview|hired|career|business|client|customers?|launch|startup|freelance|portfolio|cv|resume)\b'),
      const [
        'Update your CV, profile or portfolio',
        'List three people or companies you would like to reach',
        'Send one message to someone who can help',
        'Prepare a one-minute answer to "what do you do?"',
      ],
    ),
    _Topic(
      RegExp(r'\b(love|partner|relationship|dating|date|marry|marriage|wedding|boyfriend|girlfriend|husband|wife|family|baby|friends?)\b'),
      const [
        'Write three things you want in a relationship',
        'Reach out to one person you have been meaning to',
        'Do one thing this week that makes you feel like yourself',
        'Say yes to one invitation',
      ],
    ),
    _Topic(
      RegExp(r'\b(write|writing|book|novel|song|music|art|paint|film|podcast|blog|channel|record|create|design|sing|dance)\b'),
      const [
        'Make something terrible for ten minutes, just to begin',
        'Pick a time each week that is only for this',
        'Show one unfinished piece to someone you trust',
        'Set a date to finish a first small version',
      ],
    ),
  ];

  static const _byCategory = <WishCategory, List<String>>{
    WishCategory.career: [
      'Write down what success looks like in one sentence',
      'List one skill you would need to get there',
      'Ask one person who has done it for advice',
    ],
    WishCategory.love: [
      'Write down what you most want to feel',
      'Do one kind thing for someone close to you',
      'Spend 15 minutes on something that makes you glow',
    ],
    WishCategory.health: [
      'Pick one small habit and attach it to your morning',
      'Write down why this matters to you',
      'Tell someone who will check in on you',
    ],
    WishCategory.travel: [
      'Save a photo of the place that made you want this',
      'Look up the cheapest time to go',
      'Make a rough list of what it would cost',
    ],
    WishCategory.home: [
      'Describe your ideal home in five words',
      'Tidy one small corner to feel what it is like',
      'Save three pictures that match the feeling you want',
    ],
    WishCategory.daily: [],
  };

  /// Good for any wish, used to fill the list up.
  static const _anyWish = <String>[
    'Spend 15 minutes on it today',
    'Write down the very first step in your own words',
    'Choose a date to look at your progress',
    'Tell one person about this wish',
    'Notice and write down one thing that moved this week',
  ];
}

class _Topic {
  final RegExp words;
  final List<String> steps;
  const _Topic(this.words, this.steps);
}
