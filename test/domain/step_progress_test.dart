import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/domain/plan/step_progress.dart';

void main() {
  test('four taps follow one strict cycle and then repeat it', () {
    StepProgress value = StepProgress.notStarted;
    final List<StepProgress> seen = <StepProgress>[value];

    for (int tap = 0; tap < 8; tap++) {
      value = value.next();
      seen.add(value);
    }

    expect(seen, <StepProgress>[
      StepProgress.notStarted,
      StepProgress.partialUp,
      StepProgress.completed,
      StepProgress.partialDown,
      StepProgress.notStarted,
      StepProgress.partialUp,
      StepProgress.completed,
      StepProgress.partialDown,
      StepProgress.notStarted,
    ]);
  });

  test('the two half states have distinct persisted codes', () {
    expect(StepProgress.partialUp.code, 1);
    expect(StepProgress.partialDown.code, 3);
    expect(StepProgress.tryParse(1), StepProgress.partialUp);
    expect(StepProgress.tryParse(3), StepProgress.partialDown);
  });

  test('both half states credit fifty percent', () {
    expect(StepProgress.partialUp.fraction, 0.5);
    expect(StepProgress.partialDown.fraction, 0.5);
    expect(StepProgress.partialUp.isPartial, isTrue);
    expect(StepProgress.partialDown.isPartial, isTrue);
    expect(StepProgress.completed.fraction, 1);
    expect(StepProgress.notStarted.fraction, 0);
  });
}
