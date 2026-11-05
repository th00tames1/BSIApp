import 'package:bsi_field/src/app_prefs.dart';
import 'package:bsi_field/src/l10n.dart';
import 'package:bsi_field/src/models/draft.dart';
import 'package:bsi_field/src/screens/bsi_table_screen.dart';
import 'package:bsi_field/src/screens/result_screen.dart';
import 'package:bsi_field/src/screens/settings_screen.dart';
import 'package:bsi_field/src/screens/about_screen.dart';
import 'package:bsi_field/src/screens/manual_screen.dart';
import 'package:bsi_field/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Exercise late native callbacks without creating a real WKWebView on the host.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _WebPlatform extends WebViewPlatform {
  late _WebDelegate delegate;
  int scripts = 0;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _WebController(params, this);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => delegate = _WebDelegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _WebWidget(params);
}

class _WebDelegate extends PlatformNavigationDelegate {
  _WebDelegate(super.params) : super.implementation();
  late PageEventCallback finished;
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
}

class _WebController extends PlatformWebViewController {
  _WebController(super.params, this.owner) : super.implementation();
  final _WebPlatform owner;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate d,
  ) async {}
  @override
  Future<void> loadFlutterAsset(String key) async {}
  @override
  Future<void> runJavaScript(String script) async {
    owner.scripts++;
  }
}

class _WebWidget extends PlatformWebViewWidget {
  _WebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const Text('HOST_WEBVIEW_PLACEHOLDER');
}

void main() {
  setUp(() {
    appLang.value = AppLang.ko;
    demoMode.value = true;
  });
  tearDown(() => demoMode.value = false);

  Future<GlobalKey<NavigatorState>> openResult(WidgetTester t) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: AppTheme.light(),
        home: const Scaffold(body: Text('ROOT_NAVIGATION_ANCHOR')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ResultScreen(draft: SurveyDraft()..dbhCm = 35),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 3500));
    await t.pump(const Duration(milliseconds: 350));
    expect(find.byType(BsiTableScreen), findsOneWidget);
    return nav;
  }

  testWidgets('시연 판정표를 일찍 닫아도 결과 화면을 추가로 pop하지 않는다', (t) async {
    final nav = await openResult(t);
    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(find.byType(ResultScreen), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(find.byType(ResultScreen), findsOneWidget);
    expect(find.text('ROOT_NAVIGATION_ANCHOR'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('시연 타이머는 사용자가 나중에 연 다른 화면을 닫지 않는다', (t) async {
    final nav = await openResult(t);
    nav.currentState!.pop();
    await t.pumpAndSettle();
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('USER_OPENED_SCREEN')),
      ),
    );
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(find.text('USER_OPENED_SCREEN'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('시연 결과를 떠난 뒤 예약 작업이 원래 화면에 영향을 주지 않는다', (t) async {
    final nav = await openResult(t);
    nav.currentState!.popUntil((route) => route.isFirst);
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 6));
    expect(find.text('ROOT_NAVIGATION_ANCHOR'), findsOneWidget);
    expect(nav.currentState!.canPop(), isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('설명서 로딩 중 뒤로간 뒤 늦은 WebView 완료 콜백은 무시한다', (t) async {
    demoMode.value = false;
    final web = _WebPlatform();
    WebViewPlatform.instance = web;
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: AppTheme.light(),
        home: const Scaffold(body: Text('ROOT')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const ManualScreen()),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    final callback = web.delegate.finished;
    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(() => callback('file:///manual/index.html'), returnsNormally);
    expect(web.scripts, 0);
    expect(find.text('ROOT'), findsOneWidget);
  });

  for (final child in <Widget>[const AboutScreen(), const BsiTableScreen()]) {
    testWidgets('설정 → ${child.runtimeType} → 뒤로 두 번을 반복해도 루트가 남는다', (t) async {
      demoMode.value = false;
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: AppTheme.light(),
          home: const Scaffold(body: Text('ROOT')),
        ),
      );
      for (var i = 0; i < 3; i++) {
        nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        );
        await t.pumpAndSettle();
        final label = child is AboutScreen ? '정보' : '존치·벌채 판정표';
        await t.scrollUntilVisible(
          find.text(label),
          350,
          scrollable: find.byType(Scrollable).first,
        );
        await t.tap(find.text(label));
        await t.pumpAndSettle();
        expect(find.byType(child.runtimeType), findsOneWidget);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.text('ROOT'), findsOneWidget);
        expect(await nav.currentState!.maybePop(), isFalse);
        expect(t.takeException(), isNull);
      }
    });
  }
}
