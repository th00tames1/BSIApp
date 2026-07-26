import 'package:flutter/material.dart';

/// 앱 표시 언어. 현장 조사자는 대부분 한국어를 쓰므로 기본값은 한국어다.
enum AppLang { ko, en }

final ValueNotifier<AppLang> appLang = ValueNotifier(AppLang.ko);

/// 화면 문구. 키 테이블 대신 호출부에 원문을 그대로 두어(코드가 읽히는 쪽이
/// 중요한 소규모 2개 국어 앱) 번역 누락이 눈에 바로 보이게 한다.
String tr(String ko, String en) => appLang.value == AppLang.en ? en : ko;

/// 판정·수종 문자열은 DB에 그대로 저장되고 비교에도 쓰이므로 **값은 한국어로 두고
/// 화면에 낼 때만** 이 함수로 옮긴다. (번역해서 저장하면 기존 기록과 어긋난다.)
String verdictLabel(String verdict) {
  if (verdict.isEmpty) return '';
  return verdict == '벌채' ? tr('벌채', 'Fell') : tr('존치', 'Retain');
}

String speciesLabel(String species) {
  if (species.isEmpty) return '';
  return species == '소나무' ? tr('소나무', 'Korean red pine') : species;
}

extension AppLangX on AppLang {
  String get label => this == AppLang.en ? 'English' : '한국어';
  String get code => this == AppLang.en ? 'en' : 'ko';
}

AppLang langFromCode(String? code) =>
    code == 'en' ? AppLang.en : AppLang.ko;
