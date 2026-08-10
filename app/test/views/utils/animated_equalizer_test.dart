import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmr_music_room/views/utils/animated_equalizer.dart';

List<double> _barHeights(WidgetTester tester) {
  return tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(AnimatedEqualizer),
          matching: find.byType(Container),
        ),
      )
      .map((container) => (container.constraints?.maxHeight) ?? 0)
      .toList();
}

void main() {
  testWidgets('renders barCount bars honoring size and color', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: AnimatedEqualizer(
            isPlaying: false,
            color: Colors.red,
            size: 40,
            barCount: 5,
          ),
        ),
      ),
    );

    final containers = tester.widgetList<Container>(
      find.descendant(
        of: find.byType(AnimatedEqualizer),
        matching: find.byType(Container),
      ),
    );
    expect(containers, hasLength(5));
    for (final container in containers) {
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.red);
    }

    final box = tester.getSize(find.byType(AnimatedEqualizer));
    expect(box.width, 40);
    expect(box.height, 40);
  });

  testWidgets('freezes to a fixed still pattern when isPlaying is false', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: AnimatedEqualizer(isPlaying: false, size: 40)),
      ),
    );
    await tester.pump();
    final firstHeights = _barHeights(tester);

    await tester.pump(const Duration(milliseconds: 300));
    final secondHeights = _barHeights(tester);

    expect(secondHeights, firstHeights);
  });

  testWidgets('animates bar heights while isPlaying is true', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: AnimatedEqualizer(isPlaying: true, size: 40)),
      ),
    );
    await tester.pump();
    final firstHeights = _barHeights(tester);

    await tester.pump(const Duration(milliseconds: 300));
    final secondHeights = _barHeights(tester);

    expect(secondHeights, isNot(equals(firstHeights)));
  });

  testWidgets('freezes back to the still pattern when toggled off', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: AnimatedEqualizer(isPlaying: true, size: 40)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: AnimatedEqualizer(isPlaying: false, size: 40)),
      ),
    );
    await tester.pump();
    final pausedHeights = _barHeights(tester);

    await tester.pump(const Duration(milliseconds: 300));
    final laterHeights = _barHeights(tester);

    expect(laterHeights, pausedHeights);
  });
}
