/// Daily affirmation, split so the closing phrase can be set in italic gold.
typedef Affirmation = ({String lead, String accent});

const _all = <Affirmation>[
  (lead: 'Everything is always working out ', accent: 'for me.'),
  (lead: 'Good things are already ', accent: 'on their way.'),
  (lead: 'I notice what is ', accent: 'going right.'),
  (lead: 'Words are powerful. Words are ', accent: 'spells.'),
  (lead: 'Today holds something ', accent: 'worth looking forward to.'),
  (lead: 'My mind looks for ', accent: 'proof that it works out.'),
  (lead: 'I am allowed to expect ', accent: 'the best.'),
  (lead: 'Small joys are ', accent: 'still magic.'),
  (lead: 'I attract what I ', accent: 'quietly believe.'),
  (lead: 'Luck follows ', accent: 'the hopeful.'),
  (lead: 'The life I want is ', accent: 'already finding me.'),
  (lead: 'I look for the good, and ', accent: 'it shows up.'),
];

Affirmation affirmationFor(DateTime day) {
  final dayOfYear = day.difference(DateTime(day.year)).inDays;
  return _all[dayOfYear % _all.length];
}
