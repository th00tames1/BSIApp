import 'package:bsi_field/src/app_prefs.dart';
import 'package:bsi_field/src/l10n.dart';
import 'package:bsi_field/src/models/draft.dart';
import 'package:bsi_field/src/screens/result_screen.dart';
import 'package:bsi_field/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    appLang.value = AppLang.ko;
    demoMode.value = false;
  });
  for (final size in [const Size(375, 1024), const Size(1024, 768)]) {
    testWidgets('미촬영 방위 입력 취소 후 결과와 루트가 유지된다 $size', (t) async {
      await t.binding.setSurfaceSize(size);
      addTearDown(() => t.binding.setSurfaceSize(null));
      final nav = GlobalKey<NavigatorState>();
      final draft = SurveyDraft()..dbhCm = 35;
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: AppTheme.light(),
          home: const Scaffold(body: Text('ROOT')),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => ResultScreen(draft: draft)),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('동 +'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('동 +'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, '취소'));
      await t.pumpAndSettle();
      expect(find.byType(ResultScreen), findsOneWidget);
      expect(draft.results, isEmpty);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('ROOT'), findsOneWidget);
      expect(nav.currentState!.canPop(), isFalse);
      expect(t.takeException(), isNull);
    });

    testWidgets('미촬영 방위 잘못된 값, 저장, 초기화가 정상 동작한다 $size', (t) async {
      await t.binding.setSurfaceSize(size);
      addTearDown(() => t.binding.setSurfaceSize(null));
      final draft = SurveyDraft()..dbhCm = 35;
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ResultScreen(draft: draft),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('동 +'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('동 +'));
      await t.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      );
      await t.enterText(fields.at(0), '3');
      await t.enterText(fields.at(1), '101');
      await t.tap(find.widgetWithText(FilledButton, '저장'));
      await t.pumpAndSettle();
      expect(find.text('그을음 면적비는 0 ~ 100 % 범위로 입력하세요'), findsOneWidget);
      expect(draft.results, isEmpty);
      await t.enterText(fields.at(1), '50');
      await t.tap(find.widgetWithText(FilledButton, '저장'));
      await t.pumpAndSettle();
      expect(draft.results[Azimuth.east]!.manual, isTrue);
      expect(draft.integ!.bsi, 6);
      expect(draft.integ!.facesUsed, 1);
      await t.scrollUntilVisible(
        find.text('동 50%'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('동 50%'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, '입력 초기화'));
      await t.pumpAndSettle();
      expect(draft.results, isEmpty);
      expect(find.byType(ResultScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
