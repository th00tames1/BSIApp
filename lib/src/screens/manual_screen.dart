import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n.dart';
import '../theme.dart';

/// 앱에 내장한 사용 설명서(assets/manual/index.html). 인터넷 없이 열린다.
///
/// 설명서 원본은 웹 설명서와 같은 HTML이며, 앱의 라이트/다크 테마를 그대로 따른다.
/// 설명서 안의 차례 링크(#장)는 페이지 안에서 이동하고, 외부 주소로는 나가지 않는다.
class ManualScreen extends StatefulWidget {
  const ManualScreen({super.key});

  static const String asset = 'assets/manual/index.html';

  @override
  State<ManualScreen> createState() => _ManualScreenState();
}

class _ManualScreenState extends State<ManualScreen> {
  late final WebViewController _web;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // 테마 지정용
      ..setNavigationDelegate(NavigationDelegate(
        // 앱 안 파일(설명서와 그 안의 #링크)만 연다.
        onNavigationRequest: (req) => req.url.startsWith('file:') || req.url.startsWith('about:')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onPageFinished: (_) {
          _applyTheme();
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadFlutterAsset(ManualScreen.asset);
  }

  void _applyTheme() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    _web.runJavaScript("document.documentElement.dataset.theme='${dark ? 'dark' : 'light'}'");
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr('사용 설명서', 'User guide'))),
      body: SafeArea(
        top: false,
        child: Stack(children: [
          WebViewWidget(controller: _web),
          if (_loading)
            Positioned.fill(
              child: ColoredBox(
                color: p.bg,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ]),
      ),
    );
  }
}
