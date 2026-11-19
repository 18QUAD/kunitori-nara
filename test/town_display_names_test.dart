import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/compact_towns.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/national_atlas.dart';
import 'package:kunitori/practice_quiz.dart';
import 'package:kunitori/quiz_stage.dart';
import 'package:kunitori/town_display_names.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Atlas atlas;
  setUpAll(() async => atlas = (await NationalAtlas.load()).atlas);
  const id = '26211010001';
  const city = '26211';

  test('review is ID-specific and survives compact metadata recreation', () {
    expect(townDisplayName(id, '田辺田辺'), '田辺');
    expect(townDisplayName('other', '田辺田辺'), '田辺田辺');
    expect(townDisplayName(id, '別の名前'), '別の名前');
    for (final name in ['河原河原', '吉里吉里', '下甲下甲', '東東']) {
      expect(townDisplayName('other', name), name);
    }
    final before = atlas.towns[id]!;
    expect(before.name, '田辺田辺');
    expect(before.displayName, '田辺');
    expect(before.population, 4911);
    final index = atlas.towns as CompactTowns;
    index.pinPrefecture('26');
    index.pinPrefecture(null);
    final after = atlas.towns[id]!;
    expect(after, isNot(same(before)));
    expect(after.displayName, '田辺');
    expect(after.name, before.name);
    expect(after.neighbors, before.neighbors);
    expect(after.area, before.area);
    expect(atlas.towns['26211012001']!.displayName, '河原河原');
  });

  test(
    'source merge preserves every town ID, canonical name and population',
    () {
      final nara = jsonDecode(
        File('assets/data/nara_metadata.json').readAsStringSync(),
      );
      final japan = jsonDecode(
        File('assets/data/japan.json').readAsStringSync(),
      );
      final merged = Atlas.fromJson({
        'cities': [...nara['cities'], ...japan['cities']],
        'towns': [...nara['towns'], ...japan['towns']],
      }, consumeTownRows: true);
      expect(
        merged.towns.keys.toList()..sort(),
        atlas.towns.keys.toList()..sort(),
      );
      for (final t in merged.towns.values) {
        final prepared = atlas.towns[t.id]!;
        expect(t.name, prepared.name, reason: t.id);
        expect(t.population, prepared.population, reason: t.id);
        expect(t.area, closeTo(prepared.area, 1e-9), reason: t.id);
        // Prepared data also contains the existing cross-prefecture connections.
        expect(prepared.neighbors, containsAll(t.neighbors), reason: t.id);
      }
      expect(merged.sourceToTown[id], id);
      expect(merged.sourceTowns[id]!.name, '田辺田辺');
      expect(merged.towns[id]!.displayName, '田辺');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  Game ready() {
    final g = Game(atlas)..setHome(id);
    g.owned.addAll(atlas.byCity[city]!.map((t) => t.id));
    g.everOwned.addAll(g.owned);
    return g;
  }

  test(
    'ongoing canonical quiz, remaining questions and campaign round trip exactly',
    () {
      final facts = atlas.facts[city]!.where((f) => f.quizEligible).toList();
      final office = facts.singleWhere((f) => f.id.endsWith(':office'));
      expect(office.answer, '田辺田辺');
      expect(office.text, contains('町は田辺。'));
      final now = DateTime.utc(2026, 11, 19);
      final questions =
          [office, ...facts.where((f) => f != office)]
              .map(
                (f) => QuizQuestion(
                  factId: f.id,
                  question: f.question,
                  answer: f.answer,
                  choices: [f.answer, ...f.decoys.take(3)],
                ),
              )
              .toList();
      final g =
          ready()
            ..quiz = Quiz(
              cityId: city,
              factId: questions.first.factId,
              question: questions.first.question,
              answer: questions.first.answer,
              choices: questions.first.choices,
              deadline: now.add(const Duration(seconds: 15)),
              remaining: questions.skip(1).toList(),
            );
      final save = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
      final restored = Game.restore(atlas, save);
      expect(restored.toJson(), save);
      expect(
        atlas.quizChoiceLabel(
          city,
          restored.quiz!.factId,
          restored.quiz!.answer,
        ),
        '田辺',
      );
      expect(atlas.quizChoiceLabel('29201', office.id, office.answer), '田辺田辺');
      expect(
        atlas.quizChoiceLabel(city, '$city:conquest:population', office.answer),
        '田辺田辺',
      );
      final owned = {...restored.owned};
      for (var i = 0; i < 5; i++) {
        expect(restored.answer(restored.quiz!.answer, now), isTrue);
        if (restored.quiz != null) {
          final next = Game.restore(
            atlas,
            jsonDecode(jsonEncode(restored.toJson())),
          );
          expect(next.quiz!.toJson(), restored.quiz!.toJson());
        }
      }
      expect(restored.owned, owned);
      expect(restored.mastered, contains(city));
    },
  );

  testWidgets('quiz shows reviewed text and submits the original answer', (
    tester,
  ) async {
    const question = QuizQuestion(
      factId: '26211:conquest:office',
      question: '制圧クイズに挑戦する町は？',
      answer: '田辺田辺',
      choices: ['田辺田辺', '河原河原', '松井', '東'],
    );
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 700,
            child: QuizStage(
              title: '京田辺市',
              question: question,
              onAnswer: (value) => selected = value,
              answerLabel:
                  (value) =>
                      atlas.quizChoiceLabel(city, question.factId, value),
            ),
          ),
        ),
      ),
    );
    expect(find.text('田辺田辺'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '田辺'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '河原河原'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '田辺'));
    expect(selected, '田辺田辺');

    final controller = PracticeQuizController([question])..start();
    await tester.pumpWidget(
      MaterialApp(
        home: PracticeQuiz(
          cityName: '京田辺市',
          questions: const [question],
          controller: controller,
          answerLabel:
              (q, value) => atlas.quizChoiceLabel(city, q.factId, value),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '田辺'));
    await tester.pump();
    expect(controller.choice, '田辺田辺');
    expect(controller.correct, isTrue);
    expect(find.textContaining('田辺田辺'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
