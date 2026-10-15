import 'package:bsi_field/src/l10n.dart';
import 'package:bsi_field/src/models/draft.dart';
import 'package:bsi_field/src/screens/bsi_table_screen.dart';
import 'package:bsi_field/src/screens/result_screen.dart';
import 'package:bsi_field/src/services/analysis_service.dart';
import 'package:bsi_field/src/services/mortality.dart';
import 'package:bsi_field/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => appLang.value = AppLang.ko);

  Future<void> open(
    WidgetTester tester, {
    double? bsi,
    double? dbh,
    bool dark = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: BsiTableScreen(bsi: bsi, dbhCm: dbh),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('BSI 14.49를 14로 반올림하고 DBH 35 cm는 유지해 55%를 표시한다', (tester) async {
    await open(tester, bsi: 14.49, dbh: 35);

    expect(find.text('BSI 14 · DBH 35 cm'), findsOneWidget);
    expect(find.text('55%'), findsOneWidget);
    expect(find.text('벌채'), findsOneWidget);
  });

  testWidgets('BSI 14.5는 15로 올림해 61%를 표시한다', (tester) async {
    await open(tester, bsi: 14.5, dbh: 35);

    expect(find.text('BSI 15 · DBH 35 cm'), findsOneWidget);
    expect(find.text('61%'), findsOneWidget);
  });

  testWidgets('BSI 10·실측 DBH 35 cm의 확률 29%와 존치를 표시한다', (tester) async {
    await open(tester, bsi: 9.51, dbh: 35);

    expect(find.text('BSI 10 · DBH 35 cm'), findsOneWidget);
    expect(find.text('29%'), findsOneWidget);
    expect(find.text('존치'), findsOneWidget);
    expect(find.text('벌채'), findsNothing);
  });

  testWidgets('반올림한 BSI로 30% 경계의 판정도 일치시킨다', (tester) async {
    await open(tester, bsi: 9.99949, dbh: 34);

    // 판정용 BSI는 10이므로 DBH 34 cm의 표 값 30%로 벌채다.
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('벌채'), findsOneWidget);
    expect(find.text('존치'), findsNothing);
  });

  testWidgets('정수 격자에서는 기존 표 값과 30% 판정 경계를 유지한다', (tester) async {
    await open(tester, bsi: 6, dbh: 20);

    expect(find.text('30%'), findsOneWidget);
    expect(find.text('벌채'), findsOneWidget);
  });

  testWidgets('스테퍼는 BSI 1·DBH 1 cm씩 이동한다', (tester) async {
    await open(tester, bsi: 14.49, dbh: 35);

    await tester.tap(find.byTooltip('BSI 증가'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('DBH 감소'));
    await tester.pumpAndSettle();

    expect(find.text('BSI 15 · DBH 34 cm'), findsOneWidget);
  });

  testWidgets('정수 BSI·1 cm 격자에서 해당 칸 하나만 선택하고 탭으로 조회한다', (tester) async {
    await open(tester, bsi: 14.49, dbh: 35);

    final selected = find.byKey(const ValueKey('bsi-table-selection'));
    expect(selected, findsOneWidget);
    expect(
      find.descendant(of: selected, matching: find.text('55')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bsi-table-row-14')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bsi-table-header-35')).hitTestable(),
      findsOneWidget,
    );

    final target = find.byKey(const ValueKey('bsi-table-14-34'));
    await tester.tap(target);
    await tester.pumpAndSettle();

    expect(find.text('BSI 14 · DBH 34 cm'), findsOneWidget);
    expect(find.text('56%'), findsOneWidget);
    expect(find.text('벌채'), findsOneWidget);
    expect(selected, findsOneWidget);
    expect(
      find.descendant(of: selected, matching: find.text('56')),
      findsOneWidget,
    );
  });

  testWidgets('열자마자 선택 칸이 중앙부에 보이고 열 머리글은 고정된다', (tester) async {
    await open(tester, bsi: 14.49, dbh: 35);

    final selected = find.byKey(const ValueKey('bsi-table-selection'));
    final horizontal = find.byKey(const ValueKey('bsi-table-horizontal'));
    final body = find.byKey(const ValueKey('bsi-table-body'));
    final header = find.byKey(const ValueKey('bsi-table-header-35'));
    final rowLabel = find.byKey(const ValueKey('bsi-table-row-14'));
    final selectedRect = tester.getRect(selected);
    expect(selected.hitTestable(), findsOneWidget);
    expect(
      selectedRect.center.dx,
      closeTo(tester.getRect(horizontal).center.dx, selectedRect.width / 2),
    );
    expect(
      selectedRect.center.dy,
      closeTo(tester.getRect(body).center.dy, selectedRect.height / 2),
    );
    expect(tester.getRect(rowLabel).top, closeTo(selectedRect.top, 1));

    final headerTop = tester.getRect(header).top;
    await tester.drag(body, const Offset(0, -64));
    await tester.pumpAndSettle();

    expect(tester.getRect(header).top, headerTop);
    expect(
      tester.getRect(rowLabel).top,
      closeTo(tester.getRect(selected).top, 1),
    );
  });

  testWidgets('표 밖의 측정값도 유지하고 결과 화면과 같은 가장자리 확률을 쓴다', (tester) async {
    await open(tester, bsi: 30, dbh: 70);

    expect(find.text('BSI 30 · DBH 70 cm'), findsOneWidget);
    expect(find.text('81%'), findsOneWidget);
    expect(find.text('벌채'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bsi-table-selection')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('측정값이 없으면 확률이나 판정을 만들지 않는다', (tester) async {
    await open(tester, bsi: double.nan, dbh: 0);

    expect(find.text('–'), findsNWidgets(2));
    expect(find.byIcon(Icons.local_fire_department), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    expect(find.text('존치'), findsNothing);
    expect(find.text('벌채'), findsNothing);
  });

  for (final (bsi, percent, verdict) in [
    (14.49, '55%', '벌채'),
    (9.51, '29%', '존치'),
  ]) {
    testWidgets('결과에서 판정표로 이동해도 $percent·$verdict와 측정값이 유지된다', (tester) async {
      final draft = SurveyDraft()
        ..dbhCm = 35
        ..isSample = true
        ..integ = BsiIntegration(
          bsi,
          35,
          bsi == 14.49 ? 0.58 : 0.2605, // 이전 방식의 캐시가 남아 있어도 새 기준으로 표시한다.
          Mortality.verdict(bsi, 35),
        );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ResultScreen(draft: draft),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(percent), findsOneWidget);
      expect(find.text('${bsi.round()}'), findsOneWidget);

      await tester.tap(find.byTooltip('판정표에서 확인'));
      await tester.pumpAndSettle();
      expect(find.text(percent), findsOneWidget);
      expect(find.text(verdict), findsOneWidget);
      expect(find.text('BSI ${bsi.round()} · DBH 35 cm'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(percent), findsOneWidget);
      expect(draft.integ!.bsi, bsi);
      expect(draft.dbhCm, 35);
    });
  }

  testWidgets('예전 캐시가 존치여도 반올림 기준으로 두 화면에서 30%·벌채를 표시한다', (tester) async {
    final draft = SurveyDraft()
      ..dbhCm = 34
      ..isSample = true
      ..integ = const BsiIntegration(9.51, 34, 0.2755, '존치');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ResultScreen(draft: draft),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('벌채 권고'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);

    await tester.tap(find.byTooltip('판정표에서 확인'));
    await tester.pumpAndSettle();
    expect(find.text('BSI 10 · DBH 34 cm'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('벌채'), findsOneWidget);
    expect(draft.integ!.bsi, 9.51);
    expect(draft.dbhCm, 34);
  });

  for (final (width, language, dark) in [
    (320.0, AppLang.ko, false),
    (393.0, AppLang.en, true),
  ]) {
    testWidgets('${width.toInt()}px ${language.code} 화면에서도 소수 측정값을 표시한다', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appLang.value = language;

      await open(tester, bsi: 14.49, dbh: 35.25, dark: dark);

      expect(find.text('BSI 14 · DBH 35.25 cm'), findsOneWidget);
      expect(find.text('54%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
