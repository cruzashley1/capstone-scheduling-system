// Tests for the AI review panel.
//
// The property that matters most is the one about absence: when the AI
// has nothing to say the panel must occupy no space and draw no
// placeholder, because the ranked list underneath is the actual feature
// and it works unchanged. Most of what follows is that rule from a
// different angle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling_system/models/replacement.dart';
import 'package:scheduling_system/widgets/ai_review_panel.dart';

const _names = {
  'EMP-1': 'Juan Dela Cruz',
  'EMP-2': 'Maria Santos',
};

String? _nameFor(String id) => _names[id];

AiReview _review({
  String recommendedId = 'EMP-1',
  String confidence = 'strong',
  String rationale = 'Rested, and knows the post.',
  String? risk,
  String? runnerUpId,
  String? runnerUpTradeoff,
  String? model,
}) {
  return AiReview(
    recommendedId: recommendedId,
    confidence: confidence,
    rationale: rationale,
    risk: risk,
    runnerUpId: runnerUpId,
    runnerUpTradeoff: runnerUpTradeoff,
    model: model,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  AiReview? review,
  bool isLoading = false,
  String? topRankedId,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AiReviewPanel(
        review: review,
        isLoading: isLoading,
        topRankedId: topRankedId,
        nameFor: _nameFor,
      ),
    ),
  ));
}

void main() {
  group('when the AI has nothing to say', () {
    testWidgets('no review renders nothing at all', (tester) async {
      await _pump(tester, review: null);
      expect(find.byType(Card), findsNothing);
      expect(find.textContaining('AI'), findsNothing);
      // Not a zero-height placeholder either — the list below should sit
      // where it always sat.
      expect(tester.getSize(find.byType(AiReviewPanel)), Size.zero);
    });

    testWidgets('a recommendation naming somebody off the shortlist is '
        'dropped rather than displayed', (tester) async {
      await _pump(tester, review: _review(recommendedId: 'GHOST-99'));
      expect(tester.getSize(find.byType(AiReviewPanel)), Size.zero);
    });

    testWidgets('loading shows progress, and says what it is doing',
        (tester) async {
      await _pump(tester, review: null, isLoading: true);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('Reviewing'), findsOneWidget);
    });
  });

  group('the recommendation', () {
    testWidgets('names the guard and gives the written reason',
        (tester) async {
      await _pump(tester, review: _review());
      expect(find.text('Juan Dela Cruz'), findsOneWidget);
      expect(find.text('Rested, and knows the post.'), findsOneWidget);
      expect(find.text('AI Recommendation'), findsOneWidget);
    });

    testWidgets('confidence is worded, not numeric', (tester) async {
      await _pump(tester, review: _review(confidence: 'strong'));
      expect(find.text('Strong fit'), findsOneWidget);

      await _pump(tester, review: _review(confidence: 'weak'));
      expect(find.text('Weak fit'), findsOneWidget);

      // An unrecognised value must not blank the chip.
      await _pump(tester, review: _review(confidence: 'nonsense'));
      expect(find.text('Moderate fit'), findsOneWidget);
    });

    testWidgets('the model is named, so an admin can see what produced it',
        (tester) async {
      await _pump(tester, review: _review(model: 'gemini-2.5-flash'));
      expect(find.text('gemini-2.5-flash'), findsOneWidget);
    });
  });

  group('the things chips cannot say', () {
    testWidgets('a risk is shown when there is one', (tester) async {
      await _pump(tester,
          review: _review(risk: 'Leaves Gate 3 on one guard overnight.'));
      expect(find.text('Leaves Gate 3 on one guard overnight.'),
          findsOneWidget);
    });

    testWidgets('and no empty warning line when there is not', (tester) async {
      await _pump(tester, review: _review(risk: null));
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('a blank risk string is treated as no risk', (tester) async {
      await _pump(tester, review: _review(risk: '   '));
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('the runner-up is named with why not them', (tester) async {
      await _pump(tester,
          review: _review(
            runnerUpId: 'EMP-2',
            runnerUpTradeoff: 'Has covered twice this month already.',
          ));
      // The runner-up line is a RichText, so the finder has to be told
      // to look inside spans — without findRichText it matches nothing
      // and the assertion passes for the wrong reason.
      expect(find.textContaining('Maria Santos', findRichText: true),
          findsOneWidget);
      expect(
          find.textContaining('Has covered twice this month already.',
              findRichText: true),
          findsOneWidget);
    });

    testWidgets('a runner-up who has dropped off the shortlist is not named',
        (tester) async {
      await _pump(tester,
          review: _review(runnerUpId: 'GHOST-99', runnerUpTradeoff: 'x'));
      expect(find.textContaining('Runner-up', findRichText: true),
          findsNothing);
      // ...and the recommendation itself still stands.
      expect(find.text('Juan Dela Cruz'), findsOneWidget);
    });
  });

  group('the disagreement — the clearest evidence of judgement', () {
    testWidgets('is called out when the AI passed over the rules\' first pick',
        (tester) async {
      await _pump(tester,
          review: _review(recommendedId: 'EMP-1'), topRankedId: 'EMP-2');
      expect(find.textContaining('Ranked differently'), findsOneWidget);
    });

    testWidgets('and stays quiet when they agree', (tester) async {
      await _pump(tester,
          review: _review(recommendedId: 'EMP-1'), topRankedId: 'EMP-1');
      expect(find.textContaining('Ranked differently'), findsNothing);
    });

    testWidgets('with no ranking to compare against, it claims nothing',
        (tester) async {
      await _pump(tester, review: _review(), topRankedId: null);
      expect(find.textContaining('Ranked differently'), findsNothing);
    });
  });

  group('AiReview.fromJson', () {
    test('reads a full response', () {
      final r = AiReview.fromJson(const {
        'recommendedId': 'EMP-1',
        'confidence': 'strong',
        'rationale': 'Because.',
        'risk': 'Careful.',
        'runnerUpId': 'EMP-2',
        'runnerUpTradeoff': 'Busy.',
        'model': 'gemini-2.5-flash',
      });
      expect(r.recommendedId, 'EMP-1');
      expect(r.risk, 'Careful.');
      expect(r.runnerUpId, 'EMP-2');
      expect(r.model, 'gemini-2.5-flash');
    });

    test('survives a response missing every optional field', () {
      final r = AiReview.fromJson(const {'recommendedId': 'EMP-1'});
      expect(r.recommendedId, 'EMP-1');
      expect(r.confidence, 'moderate');
      expect(r.rationale, '');
      expect(r.risk, isNull);
      expect(r.runnerUpId, isNull);
    });

    test('differsFrom needs both sides to mean anything', () {
      final r = AiReview.fromJson(const {'recommendedId': 'EMP-1'});
      expect(r.differsFrom('EMP-2'), isTrue);
      expect(r.differsFrom('EMP-1'), isFalse);
      expect(r.differsFrom(null), isFalse);
      expect(AiReview.fromJson(const {}).differsFrom('EMP-2'), isFalse);
    });
  });
}
