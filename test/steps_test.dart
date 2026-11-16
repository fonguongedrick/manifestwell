// Breaking a wish into small steps: the suggester, the model, the state, and
// the sheet people use.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manifestwell/models/wish.dart';
import 'package:manifestwell/screens/vault_screen.dart';
import 'package:manifestwell/state/app_state.dart';
import 'package:manifestwell/theme.dart';
import 'package:manifestwell/utils/step_suggester.dart';
import 'package:manifestwell/widgets/backdrop.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_well_backend.dart';
import 'test_fonts.dart';

Wish _wish(String text, {WishCategory category = WishCategory.career}) => Wish(
      id: 'w1',
      text: text,
      kind: WishKind.big,
      category: category,
      createdAt: DateTime(2026, 11, 1),
    );

Future<AppState> _load({FakeWellBackend? backend}) async {
  SharedPreferences.setMockInitialValues({});
  var tick = 0;
  return AppState.load(
    now: () => DateTime(2026, 11, 10, 12).add(Duration(seconds: tick++)),
    backend: backend,
  );
}

void main() {
  setUpAll(loadAppFonts);
  shotsMain();

  group('StepSuggester', () {
    test('a saving wish gets money steps', () {
      final steps = StepSuggester.suggest(_wish('Save 5000 for a deposit'));
      expect(steps.first, contains('amount'));
      expect(steps.any((s) => s.contains('savings pot')), isTrue);
    });

    test('a fitness wish gets fitness steps', () {
      final steps = StepSuggester.suggest(_wish('Run a half marathon', category: WishCategory.health));
      expect(steps.any((s) => s.contains('session')), isTrue);
    });

    test('a wish that is about two things gets steps for both', () {
      final steps = StepSuggester.suggest(_wish('Save for a house', category: WishCategory.home), max: 8);
      expect(steps.any((s) => s.contains('savings pot')), isTrue);
      expect(steps.any((s) => s.contains('must-haves')), isTrue);
    });

    test('a wish it does not recognise still gets sensible steps from its category', () {
      final steps = StepSuggester.suggest(_wish('Be happier', category: WishCategory.love));
      expect(steps, isNotEmpty);
      expect(steps.length, 5);
    });

    test('never more than asked for, never repeated, never blank or too long', () {
      for (final text in ['Save money and learn a language and run and travel', 'x', 'Move house']) {
        for (final cat in WishCategory.values) {
          final steps = StepSuggester.suggest(_wish(text, category: cat), max: 6);
          expect(steps.length, lessThanOrEqualTo(6));
          expect(steps.toSet().length, steps.length, reason: '$text/$cat has repeats');
          for (final s in steps) {
            expect(s.trim(), isNotEmpty);
            expect(s.length, lessThanOrEqualTo(WishStep.maxLength));
          }
        }
      }
    });

    test('the same wish always gets the same steps', () {
      final w = _wish('Learn to code');
      expect(StepSuggester.suggest(w), StepSuggester.suggest(w));
    });

    test('words are matched whole: "praise" is not the money word "raise"', () {
      final steps = StepSuggester.suggest(_wish('Praise from my mum', category: WishCategory.love), max: 8);
      expect(steps.any((s) => s.contains('savings pot')), isFalse);
      // ...while the real word does match.
      expect(StepSuggester.suggest(_wish('Get a raise'), max: 8).any((s) => s.contains('savings pot')), isTrue);
    });
  });

  group('WishStep and Wish', () {
    test('steps survive a save and reload, done or not', () {
      final w = _wish('Learn Spanish').copyWith(steps: [
        const WishStep(id: 'a', text: 'Pick a course'),
        WishStep(id: 'b', text: 'Book three sessions', doneAt: DateTime(2026, 11, 5)),
      ]);
      final back = Wish.fromJson(w.toJson());
      expect(back.steps.map((s) => s.text), ['Pick a course', 'Book three sessions']);
      expect(back.steps.map((s) => s.done), [false, true]);
      expect(back.steps[1].doneAt, DateTime(2026, 11, 5));
    });

    test('a wish saved before steps existed still loads, with none', () {
      final json = _wish('Old wish').toJson()..remove('steps');
      expect(Wish.fromJson(json).steps, isEmpty);
    });

    test('one damaged step is dropped without losing the wish or the other steps', () {
      final json = _wish('Mixed').toJson();
      json['steps'] = [
        {'id': 'ok', 'text': 'Fine step', 'doneAt': null},
        'not a map',
        {'id': 'blank', 'text': '   '},
        {'text': 'no id'},
        {'id': 'ok2', 'text': 'Also fine', 'doneAt': 'not a date'},
      ];
      final w = Wish.fromJson(json);
      expect(w.steps.map((s) => s.id), ['ok', 'ok2']);
      expect(w.steps.last.done, isFalse); // an unreadable date is "not done", not a crash
    });

    test('progress counts finished steps', () {
      final w = _wish('x').copyWith(steps: [
        WishStep(id: 'a', text: 'a', doneAt: DateTime(2026)),
        const WishStep(id: 'b', text: 'b'),
        const WishStep(id: 'c', text: 'c'),
      ]);
      expect(w.progress, (done: 1, total: 3));
      expect(_wish('y').progress, (done: 0, total: 0));
    });

    test('toggling flips done and keeps the rest', () {
      const s = WishStep(id: 'a', text: 'Do it');
      final now = DateTime(2026, 11, 10);
      expect(s.toggled(now).doneAt, now);
      expect(s.toggled(now).toggled(now).done, isFalse);
      expect(s.toggled(now).text, 'Do it');
    });
  });

  group('AppState steps', () {
    test('adds steps, skipping blanks and repeats, and trims long ones', () async {
      final state = await _load();
      final w = (await state.cast('Save for a house', WishKind.big, WishCategory.home))!;
      final added = await state.addSteps(w.id, ['Open a savings pot', '  ', 'open a SAVINGS pot', 'Set a budget']);
      expect(added, 2);
      expect(state.myWish(w.id)!.steps.map((s) => s.text), ['Open a savings pot', 'Set a budget']);

      await state.addSteps(w.id, ['x' * 300]);
      expect(state.myWish(w.id)!.steps.last.text.length, WishStep.maxLength);
    });

    test('an emoji at the cut-off is never split in half', () async {
      final state = await _load();
      final w = (await state.cast('Wish', WishKind.big, WishCategory.home))!;
      await state.addSteps(w.id, ['${'a' * (WishStep.maxLength - 1)}🎉🎉']);
      final text = state.myWish(w.id)!.steps.single.text;
      expect(text.runes.length, WishStep.maxLength);
      // Every code unit pairs up: no lone surrogate that would show as a broken glyph.
      expect(() => String.fromCharCodes(text.runes), returnsNormally);
      expect(text.endsWith('🎉'), isTrue);
    });

    test('a wish holds at most the limit', () async {
      final state = await _load();
      final w = (await state.cast('Wish', WishKind.big, WishCategory.home))!;
      final added = await state.addSteps(w.id, [for (var i = 0; i < 30; i++) 'Step number $i']);
      expect(added, WishStep.maxPerWish);
      expect(state.myWish(w.id)!.steps.length, WishStep.maxPerWish);
      expect(await state.addSteps(w.id, ['One more']), 0);
    });

    test('every step gets its own id, even when added together', () async {
      final state = await _load();
      final w = (await state.cast('Wish', WishKind.big, WishCategory.home))!;
      await state.addSteps(w.id, ['One', 'Two', 'Three']);
      await state.addSteps(w.id, ['Four']);
      final ids = state.myWish(w.id)!.steps.map((s) => s.id).toList();
      expect(ids.toSet().length, 4);
    });

    test('ticking a step and un-ticking it', () async {
      final state = await _load();
      final w = (await state.cast('Wish', WishKind.big, WishCategory.home))!;
      await state.addSteps(w.id, ['One', 'Two']);
      final first = state.myWish(w.id)!.steps.first.id;
      await state.toggleStep(w.id, first);
      expect(state.myWish(w.id)!.progress, (done: 1, total: 2));
      await state.toggleStep(w.id, first);
      expect(state.myWish(w.id)!.progress, (done: 0, total: 2));
    });

    test('removing a step leaves the others', () async {
      final state = await _load();
      final w = (await state.cast('Wish', WishKind.big, WishCategory.home))!;
      await state.addSteps(w.id, ['One', 'Two', 'Three']);
      await state.removeStep(w.id, state.myWish(w.id)!.steps[1].id);
      expect(state.myWish(w.id)!.steps.map((s) => s.text), ['One', 'Three']);
    });

    test('an unknown wish or step is ignored, not a crash', () async {
      final state = await _load();
      expect(await state.addSteps('nope', ['x']), 0);
      await state.toggleStep('nope', 'nope');
      await state.removeStep('nope', 'nope');
      final w = (await state.cast('Wish', WishKind.big, WishCategory.home))!;
      await state.toggleStep(w.id, 'no-such-step');
      expect(state.myWish(w.id)!.steps, isEmpty);
    });

    test('steps are saved on the device and come back after a restart', () async {
      final state = await _load();
      final w = (await state.cast('Wish', WishKind.big, WishCategory.home))!;
      await state.addSteps(w.id, ['One', 'Two']);
      await state.toggleStep(w.id, state.myWish(w.id)!.steps.first.id);

      // A new AppState reading the same saved data, as after closing the app.
      final again = await AppState.load();
      expect(again.myWish(w.id)!.steps.map((s) => s.text), ['One', 'Two']);
      expect(again.myWish(w.id)!.progress, (done: 1, total: 2));
    });

    test('a signed-in account uploads each change; a guest does not', () async {
      final backend = FakeWellBackend(account: 'ada@example.com');
      final state = await _load(backend: backend);
      final w = (await state.cast('Wish', WishKind.big, WishCategory.home))!;
      backend.cloud.clear();
      await state.addSteps(w.id, ['One']);
      expect(backend.cloud[w.id]!.steps.map((s) => s.text), ['One']);

      final guestBackend = FakeWellBackend();
      final guest = await _load(backend: guestBackend);
      final gw = (await guest.cast('Wish', WishKind.big, WishCategory.home))!;
      await guest.addSteps(gw.id, ['One']);
      expect(guestBackend.cloud, isEmpty);
    });

    test('a change counts as the newest edit, so it wins when devices disagree', () async {
      final state = await _load();
      final w = (await state.cast('Wish', WishKind.big, WishCategory.home))!;
      final before = state.myWish(w.id)!.modified;
      await state.addSteps(w.id, ['One']);
      expect(state.myWish(w.id)!.modified.isAfter(before), isTrue);
    });

    test('steps stay with a wish when it is resolved, and are in the export', () async {
      final state = await _load();
      final w = (await state.cast('Wish', WishKind.big, WishCategory.home))!;
      await state.addSteps(w.id, ['Book the viewing']);
      await state.resolve(w.id, WishStatus.granted);
      expect(state.myWish(w.id)!.steps.single.text, 'Book the viewing');
      expect(state.exportData(), contains('Book the viewing'));
    });

  });

  group('Steps sheet', () {
    Future<AppState> open(WidgetTester t, {String text = 'Save for a house'}) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final state = await _load();
      await state.cast(text, WishKind.big, WishCategory.home);
      await t.binding.setSurfaceSize(const Size(430, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: MW.theme(),
          home: Scaffold(body: VaultScreen(onCast: () {})),
        ),
      ));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 120));
      }
      return state;
    }

    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 120));
      }
    }

    testWidgets('a wish with no steps invites you to make some', (t) async {
      await open(t);
      expect(find.text('Break it into small steps'), findsOneWidget);
    });

    testWidgets('"Break it down for me" fills in five starting steps', (t) async {
      final state = await open(t);
      await t.tap(find.text('Break it into small steps'));
      await settle(t);
      expect(find.text('Small steps'.toUpperCase()), findsOneWidget);
      await t.tap(find.text('BREAK IT DOWN FOR ME'));
      await settle(t);
      expect(state.activeWishes.single.steps.length, 5);
      expect(find.text('0 of 5 done'), findsOneWidget);
    });

    testWidgets('ticking steps moves the progress, and the card behind it follows', (t) async {
      final state = await open(t);
      await t.tap(find.text('Break it into small steps'));
      await settle(t);
      await t.tap(find.text('BREAK IT DOWN FOR ME'));
      await settle(t);
      final first = state.activeWishes.single.steps.first.text;
      await t.tap(find.text(first));
      await settle(t);
      expect(find.text('1 of 5 done'), findsOneWidget);
      expect(state.activeWishes.single.progress, (done: 1, total: 5));
    });

    testWidgets('finishing the last step offers to revisit the wish', (t) async {
      final state = await open(t);
      await state.addSteps(state.activeWishes.single.id, ['Only step']);
      await settle(t); // let the card redraw with its new steps
      await t.tap(find.text('0 of 1 small steps'));
      await settle(t);
      expect(find.text('Every step is done.'), findsNothing);
      await t.tap(find.text('Only step'));
      await settle(t);
      expect(find.text('Every step is done.'), findsOneWidget);
      await t.tap(find.text('REVISIT THIS WISH'));
      await settle(t);
      expect(find.text('REVISIT YOUR WISH'), findsOneWidget);
    });

    testWidgets('typing a step and adding it', (t) async {
      final state = await open(t);
      await state.addSteps(state.activeWishes.single.id, ['First']);
      await settle(t); // let the card redraw with its new steps
      await t.tap(find.text('0 of 1 small steps'));
      await settle(t);
      await t.enterText(find.byType(TextField), 'Call the bank');
      await t.pump();
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle(t);
      expect(state.activeWishes.single.steps.map((s) => s.text), ['First', 'Call the bank']);
    });

    testWidgets('tapping an idea adds it, and it leaves the ideas', (t) async {
      final state = await open(t);
      await state.addSteps(state.activeWishes.single.id, ['First']);
      await settle(t); // let the card redraw with its new steps
      await t.tap(find.text('0 of 1 small steps'));
      await settle(t);
      final idea = StepSuggester.suggest(state.activeWishes.single, max: 8)
          .firstWhere((s) => s != 'First');
      await t.tap(find.text('+  $idea'));
      await settle(t);
      expect(state.activeWishes.single.steps.map((s) => s.text), contains(idea));
      expect(find.text('+  $idea'), findsNothing);
    });

    testWidgets('removing a step', (t) async {
      final state = await open(t);
      await state.addSteps(state.activeWishes.single.id, ['Keep me', 'Remove me']);
      await settle(t); // let the card redraw with its new steps
      await t.tap(find.text('0 of 2 small steps'));
      await settle(t);
      await t.tap(find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Remove step: Remove me'));
      await settle(t);
      expect(state.activeWishes.single.steps.map((s) => s.text), ['Keep me']);
    });
  });
}

// Opt-in pictures for looking at:
//   SHOTS=1 flutter test test/steps_test.dart --update-goldens
void shotsMain() {
  final enabled = Platform.environment.containsKey('SHOTS');

  Future<AppState> setup(WidgetTester t, {bool sheet = false}) async {
    debugDisableShadows = false;
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final state = await _load();
    final w = (await state.cast('Save enough for a deposit on my first home', WishKind.big, WishCategory.home))!;
    await state.addSteps(w.id, StepSuggester.suggest(w));
    await state.toggleStep(w.id, state.myWish(w.id)!.steps[0].id);
    await state.toggleStep(w.id, state.myWish(w.id)!.steps[1].id);
    await state.cast('Practise piano every day', WishKind.big, WishCategory.daily);
    await t.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: MW.theme(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Backdrop(child: VaultScreen(onCast: () {}))),
      ),
    ));
    await t.runAsync(() async {
      await precacheImage(const AssetImage('assets/images/nebula.jpg'), t.element(find.byType(MaterialApp)));
    });
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    return state;
  }

  testWidgets('vault card with steps', skip: !enabled, (t) async {
    await setup(t);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/steps_1_vault.png'));
    debugDisableShadows = true;
  });

  testWidgets('steps sheet', skip: !enabled, (t) async {
    await setup(t);
    await t.tap(find.text('2 of 5 small steps'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/steps_2_sheet.png'));
    debugDisableShadows = true;
  });
}
