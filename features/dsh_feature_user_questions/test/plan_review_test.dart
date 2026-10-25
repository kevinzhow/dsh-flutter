import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

QuestionItem item({
  Map<String, Object?>? intent,
  int options = 2,
  bool multi = false,
  String? detail = '# **Ship fixture**\n\nRead the first paragraph.',
}) => QuestionItem(
  id: 'decision',
  question: 'Approve this?',
  detail: detail,
  multiSelect: multi,
  intent:
      intent ??
      const {
        'kind': 'plan-review',
        'approve': 'Start building',
        'callId': 'plan-call',
      },
  options: [
    const QuestionOption('Start building', 'Approve synthetic plan'),
    if (options > 1) const QuestionOption('Wait', null),
    if (options > 2) const QuestionOption('Other', null),
  ],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => loadParityFonts(findParityFontsManifest()));
  testWidgets('phone refusal keeps both decisions visible and retryable', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final pending = PendingQuestion(
      key: 'phone',
      sessionId: 's',
      questions: [item()],
      callId: 'call',
      timed: true,
    );
    addTearDown(pending.dispose);
    pending.setPhase(QuestionPhase.continued);
    var fail = true;
    pending.attachRpc((_) async {
      if (fail) throw StateError('Synthetic refusal');
      return true;
    });
    final slots = SlotRegistry();
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
    await t.pumpWidget(
      dshTestApp(
        PlanReviewPanel(
          pending: pending,
          review: planReviewOf(pending.questions)!,
          owner: testSessionOwner('s'),
          slots: slots,
          i18n: const DshI18n(DshLocale.en),
        ),
      ),
    );
    final approve = find.byKey(const ValueKey('plan-review-approve'));
    await t.tap(approve);
    await t.pump();
    expect(find.text('Synthetic refusal'), findsOneWidget);
    expect(t.getRect(approve).right, lessThanOrEqualTo(358));
    expect(
      t.getSize(find.byKey(const ValueKey('plan-review-card'))).height,
      lessThan(300),
    );
    expect(t.takeException(), isNull);
    fail = false;
    await t.tap(approve);
    await t.pump();
    expect(pending.snapshot.hidden, true);
  });
  test(
    'only supported plan intent narrows; every other choice remains generic',
    () {
      expect(planReviewOf([item()])!.approve.label, 'Start building');
      expect(planReviewOf([item()])!.callId, 'plan-call');
      for (final questions in [
        <QuestionItem>[],
        [item(), item()],
        [item(multi: true)],
        [item(options: 3)],
        [item(detail: null)],
        [
          item(intent: const {'kind': 'plan-review', 'approve': 'Missing'}),
        ],
        [
          item(intent: const {'kind': 'other'}),
        ],
      ]) {
        expect(planReviewOf(questions), isNull);
      }
    },
  );
  testWidgets(
    'approval preserves original label and waits for waterfall settlement',
    (t) async {
      final pending = PendingQuestion(
        key: 'review',
        sessionId: 's',
        questions: [item()],
        callId: 'call',
        timed: true,
      );
      addTearDown(pending.dispose);
      final sent = <List<QuestionAnswer>>[];
      pending.attachWaterfall(
        QuestionWaterfallChannel(
          deadline: null,
          resolve: (answers) async => sent.add(answers),
          reject: (_) async {},
          delegate: () async {},
        ),
      );
      final slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      final owner = testSessionOwner('s');
      await t.pumpWidget(
        dshTestApp(
          PlanReviewPanel(
            pending: pending,
            review: planReviewOf(pending.questions)!,
            owner: owner,
            slots: slots,
            i18n: const DshI18n(DshLocale.en),
          ),
        ),
      );
      expect(find.text('Ship fixture'), findsOneWidget);
      expect(find.text('Read the first paragraph.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('plan-review-approve')));
      await t.pump();
      expect(sent.single.single.toJson(), {
        'id': 'decision',
        'selected': ['Start building'],
      });
      await t.tap(find.byKey(const ValueKey('plan-review-approve')));
      await t.pump();
      expect(sent, hasLength(1));
      expect(pending.snapshot.hidden, false);
    },
  );
  testWidgets(
    'request changes hides the card without submitting a fabricated decline',
    (t) async {
      final pending = PendingQuestion(
        key: 'review',
        sessionId: 's',
        questions: [item()],
        callId: 'call',
        timed: true,
      );
      addTearDown(pending.dispose);
      var answered = false;
      pending.attachWaterfall(
        QuestionWaterfallChannel(
          deadline: null,
          resolve: (_) async {
            answered = true;
          },
          reject: (_) async {
            throw StateError('must remain pending');
          },
          delegate: () async {},
        ),
      );
      final slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      await t.pumpWidget(
        dshTestApp(
          PlanReviewPanel(
            pending: pending,
            review: planReviewOf(pending.questions)!,
            owner: testSessionOwner('s'),
            slots: slots,
            i18n: const DshI18n(DshLocale.en),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('plan-review-discuss')));
      await t.pump();
      expect(pending.snapshot.hidden, true);
      expect(answered, false);
      expect(pending.hasWaterfall, true);
    },
  );
  testWidgets(
    'failed remote answer remains editable; accepted retry hides continued review',
    (t) async {
      final pending = PendingQuestion(
        key: 'review',
        sessionId: 's',
        questions: [item()],
        callId: 'call',
        timed: true,
      );
      addTearDown(pending.dispose);
      var fail = true;
      var calls = 0;
      pending.setPhase(QuestionPhase.continued);
      pending.attachRpc((_) async {
        calls++;
        if (fail) throw StateError('Synthetic refusal');
        return true;
      });
      final slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      await t.pumpWidget(
        dshTestApp(
          PlanReviewPanel(
            pending: pending,
            review: planReviewOf(pending.questions)!,
            owner: testSessionOwner('s'),
            slots: slots,
            i18n: const DshI18n(DshLocale.en),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('plan-review-approve')));
      await t.pump();
      expect(find.textContaining('Synthetic refusal'), findsOneWidget);
      expect(pending.snapshot.hidden, false);
      fail = false;
      await t.tap(find.byKey(const ValueKey('plan-review-approve')));
      await t.pump();
      expect(calls, 2);
      expect(pending.snapshot.hidden, true);
      expect(t.takeException(), isNull);
    },
  );
}
