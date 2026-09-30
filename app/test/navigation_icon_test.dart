import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ui/navigation_icon.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('圖示切換能結束且尊重減少動畫：$reduced', (tester) async {
      Widget page(bool selected) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: NavigationIcon(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            selected: selected,
          ),
        ),
      );
      await tester.pumpWidget(page(false));
      await tester.pumpWidget(page(true));
      expect(find.byIcon(Icons.home), findsOneWidget);
      if (reduced) {
        expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
          Duration.zero,
        );
        expect(
          tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).duration,
          Duration.zero,
        );
      }
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(page(false));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
