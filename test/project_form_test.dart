import 'package:bsi_field/src/app_prefs.dart';
import 'package:bsi_field/src/screens/register_screen.dart';
import 'package:bsi_field/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 프로젝트 화면의 "다음 조사목 번호"는 말 그대로 다음 번호다.
/// 저장값 Project.treeSeq는 마지막 번호라서 화면과 1씩 차이가 난다.
void main() {
  final seqField = find.widgetWithText(
      TextFormField, '이 번호부터 자동 부여되며 이미 사용한 번호는 건너뜁니다');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await loadPrefs();
    projects.value = [];
    activeSite.value = null;
  });

  Future<void> open(WidgetTester tester, {Project? project}) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav, theme: AppTheme.light(), home: const Scaffold()));
    nav.currentState!
        .push(MaterialPageRoute(builder: (_) => ProjectScreen(project: project)));
    await tester.pumpAndSettle();
  }

  String seqText(WidgetTester tester) =>
      tester.widget<TextFormField>(seqField).controller!.text;

  testWidgets('새 프로젝트: 기본값 1, 1을 넣으면 첫 조사목이 001', (tester) async {
    await open(tester);
    expect(seqText(tester), '1');

    await tester.enterText(find.byType(TextFormField).first, '시험 조사지');
    await tester.enterText(seqField, '1');
    await tester.tap(find.text('프로젝트 생성'));
    await tester.pumpAndSettle();

    expect(activeProject!.treeSeq, 0);
    expect(peekNextTreeSeq().toString().padLeft(3, '0'), '001');
  });

  testWidgets('새 프로젝트: 21을 넣으면 첫 조사목이 021', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField).first, '시험 조사지');
    await tester.enterText(seqField, '21');
    await tester.tap(find.text('프로젝트 생성'));
    await tester.pumpAndSettle();

    expect(peekNextTreeSeq().toString().padLeft(3, '0'), '021');
  });

  testWidgets('편집: treeSeq 15면 16이 보이고 그대로 저장하면 15가 유지된다', (tester) async {
    upsertProject(site: '산청', location: '', treeSeq: 15);
    await open(tester, project: activeProject);
    expect(seqText(tester), '16');

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(activeProject!.treeSeq, 15);
    expect(peekNextTreeSeq().toString().padLeft(3, '0'), '016');
  });

  testWidgets('0을 넣어도 001부터 시작한다', (tester) async {
    upsertProject(site: '산청', location: '', treeSeq: 15);
    await open(tester, project: activeProject);
    await tester.enterText(seqField, '0');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(activeProject!.treeSeq, 0);
    expect(peekNextTreeSeq().toString().padLeft(3, '0'), '001');
  });
}
