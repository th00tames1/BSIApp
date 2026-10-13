import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 앱 안 사용 설명서(assets/manual/)가 빠짐없이 묶이는지 확인한다.
/// 설명서는 오프라인에서 열려야 하므로 외부 주소를 쓰면 안 된다.
void main() {
  final html = File('assets/manual/index.html');

  test('설명서 HTML이 있다', () {
    expect(html.existsSync(), isTrue);
  });

  test('설명서가 참조하는 이미지·글꼴 파일이 모두 있다', () {
    final s = html.readAsStringSync();
    final imgs = RegExp(r'src="(img/[^"]+)"').allMatches(s).map((m) => m.group(1)!).toSet();
    expect(imgs, isNotEmpty);
    for (final p in imgs) {
      expect(File('assets/manual/$p').existsSync(), isTrue, reason: p);
    }
    final fonts = RegExp(r'url\("\.\./(fonts/[^"]+)"\)').allMatches(s).map((m) => m.group(1)!).toSet();
    expect(fonts, isNotEmpty);
    for (final f in fonts) {
      expect(File('assets/$f').existsSync(), isTrue, reason: f);
    }
  });

  test('설명서 본문에 외부 주소가 없다(오프라인 표시)', () {
    final s = html.readAsStringSync();
    expect(RegExp(r'(src|href)="https?://').hasMatch(s), isFalse);
  });

  test('pubspec이 설명서 폴더를 자산으로 묶는다', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    expect(pub.contains('- assets/manual/\n') || pub.contains('- assets/manual/\r\n'), isTrue);
    expect(pub.contains('- assets/manual/img/'), isTrue);
  });
}
