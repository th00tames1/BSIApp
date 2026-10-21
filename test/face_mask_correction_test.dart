import 'dart:convert';
import 'dart:io';

import 'package:bsi_field/src/l10n.dart';
import 'package:bsi_field/src/models/tuning.dart';
import 'package:bsi_field/src/screens/face_adjust_screen.dart';
import 'package:bsi_field/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const triangle = [(x: .1, y: .2), (x: .4, y: .2), (x: .3, y: .8)];
void main() {
  test('exclusion data round trips without changing earlier tuning fields', () {
    final t = FaceTuning(
      groundNorm: .8,
      targetX: .3,
      targetY: .6,
      brightness: .1,
      contrast: 1.2,
      autoTone: false,
      excludedAreas: const [triangle],
    );
    final roundTrip = FaceTuning.fromJson(jsonDecode(jsonEncode(t.toJson())));
    expect(roundTrip.excludedAreas, [triangle]);
    expect(roundTrip.toJson(), t.toJson());
    expect(roundTrip.copyWith(targetX: .5).excludedAreas, [triangle]);
    expect(roundTrip.copyWith(excludedAreas: []).excludedAreas, isEmpty);
    expect(FaceTuning.fromJson({}).isDefault, isTrue);
    expect(const FaceTuning(excludedAreas: [triangle]).isDefault, isFalse);
    expect(() => roundTrip.excludedAreas.first.clear(), throwsUnsupportedError);
  });

  test(
    'invalid, enormous, crossing and degenerate boundaries cannot exclude pixels',
    () {
      final malformed = FaceTuning.fromJson({
        'excludedAreas': [
          'invalid',
          [
            {'x': 'oops', 'y': .2},
          ],
          [
            {'x': .1, 'y': .1},
            {'x': double.infinity, 'y': .2},
            {'x': .3, 'y': .3},
          ],
          [
            {'x': -.1, 'y': .1},
            {'x': .2, 'y': .2},
            {'x': .3, 'y': .3},
          ],
          for (var i = 0; i < 3; i++)
            [
              {'x': .1, 'y': .1},
              {'x': .2, 'y': .2},
            ],
        ],
      });
      expect(malformed.excludedAreas, isEmpty);
      expect(
        FaceTuning.isValidExcludedArea(const [
          (x: .1, y: .1),
          (x: .8, y: .8),
          (x: .1, y: .8),
          (x: .8, y: .1),
        ]),
        isFalse,
      );
      expect(
        FaceTuning.isValidExcludedArea(const [
          (x: .1, y: .1),
          (x: .2, y: .2),
          (x: .3, y: .3),
        ]),
        isFalse,
      );
      expect(
        FaceTuning.isValidExcludedArea(const [
          (x: .1, y: .1),
          (x: .1, y: .1),
          (x: .3, y: .3),
        ]),
        isFalse,
      );
      expect(
        FaceTuning.validatedExcludedAreas(List.filled(100, triangle)).length,
        16,
      );
      expect(
        FaceTuning.isValidExcludedArea(List.filled(65, (x: .1, y: .2))),
        isFalse,
      );
    },
  );

  late Directory temporary;
  late File image;
  setUp(() {
    appLang.value = AppLang.ko;
    temporary = Directory.systemTemp.createTempSync('bsi-exclusion-test-');
    image = File('${temporary.path}/image.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
        ),
      );
  });
  tearDown(() {
    temporary.deleteSync(recursive: true);
  });

  Future<void> open(
    WidgetTester tester, {
    FaceTuning tuning = FaceTuning.none,
    void Function(FaceTuning?)? onResult,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<FaceTuning>(
                  MaterialPageRoute(
                    builder: (_) => FaceAdjustScreen(
                      imagePath: image.path,
                      label: 'E',
                      tuning: tuning,
                    ),
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapButton(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> polygon(WidgetTester tester) async {
    final photo = tester.getRect(find.byKey(const ValueKey('adjust-photo')));
    for (final p in triangle) {
      await tester.tapAt(
        Offset(photo.left + photo.width * p.x, photo.top + photo.height * p.y),
      );
      await tester.pump();
    }
  }

  testWidgets(
    'draft needs explicit confirmation and apply returns exactly confirmed coordinates',
    (tester) async {
      FaceTuning? result;
      await open(tester, onResult: (t) => result = t);
      await tester.tap(find.text('영역 제외'));
      await tester.pump();
      await polygon(tester);
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const ValueKey('apply-adjustments')),
            )
            .onPressed,
        isNull,
      );
      await tapButton(tester, 'confirm-exclusion');
      await tapButton(tester, 'apply-adjustments');
      expect(result!.excludedAreas.length, 1);
      for (var i = 0; i < 3; i++) {
        expect(result!.excludedAreas.first[i].x, closeTo(triangle[i].x, 1e-6));
        expect(result!.excludedAreas.first[i].y, closeTo(triangle[i].y, 1e-6));
      }
      expect(result!.targetX, isNull);
      expect(result!.groundNorm, isNull);
    },
  );

  testWidgets(
    'cancel draft and undo last area do not modify target or ground',
    (tester) async {
      FaceTuning? result;
      await open(
        tester,
        tuning: const FaceTuning(
          targetX: .3,
          targetY: .5,
          groundNorm: .8,
          excludedAreas: [triangle],
        ),
        onResult: (t) => result = t,
      );
      await tester.tap(find.text('영역 제외'));
      await tester.pump();
      await polygon(tester);
      await tapButton(tester, 'cancel-exclusion');
      await tapButton(tester, 'undo-exclusion');
      await tapButton(tester, 'apply-adjustments');
      expect(result!.excludedAreas, isEmpty);
      expect(result!.targetX, .3);
      expect(result!.groundNorm, .8);
    },
  );

  testWidgets('leaving adjustment cancels confirmed edits', (tester) async {
    FaceTuning? result;
    await open(tester, onResult: (t) => result = t);
    await tester.tap(find.text('영역 제외'));
    await tester.pump();
    await polygon(tester);
    await tapButton(tester, 'confirm-exclusion');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('reset clears both confirmed exclusions and unfinished draft', (
    tester,
  ) async {
    FaceTuning? result;
    await open(
      tester,
      tuning: const FaceTuning(excludedAreas: [triangle]),
      onResult: (t) => result = t,
    );
    await tester.tap(find.text('영역 제외'));
    await tester.pump();
    await polygon(tester);
    await tester.tap(find.text('초기화'));
    await tester.pump();
    await tapButton(tester, 'apply-adjustments');
    expect(result!.isDefault, isTrue);
  });

  testWidgets(
    'target tap and ground drag preserve exclusions and tone settings',
    (tester) async {
      FaceTuning? result;
      await open(
        tester,
        tuning: const FaceTuning(
          excludedAreas: [triangle],
          brightness: .1,
          contrast: 1.1,
          autoTone: false,
        ),
        onResult: (t) => result = t,
      );
      await tester.tap(find.text('대상목'));
      await tester.pump();
      final photo = tester.getRect(find.byKey(const ValueKey('adjust-photo')));
      await tester.tapAt(photo.center);
      await tester.pump();
      await tester.tap(find.text('지표면'));
      await tester.pump();
      await tester.dragFrom(photo.center, Offset(0, photo.height * .2));
      await tester.pump();
      await tapButton(tester, 'apply-adjustments');
      expect(result!.targetX, closeTo(.5, 1e-6));
      expect(result!.targetY, closeTo(.5, 1e-6));
      expect(result!.groundNorm, greaterThan(.5));
      expect(result!.excludedAreas, [triangle]);
      expect(result!.brightness, .1);
      expect(result!.contrast, 1.1);
      expect(result!.autoTone, isFalse);
    },
  );

  for (final lang in AppLang.values) {
    testWidgets('320px ${lang.name} large font controls stay accessible', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appLang.value = lang;
      await open(tester, scale: 1.5);
      await tester.tap(
        find.text(lang == AppLang.ko ? '영역 제외' : 'Exclude area'),
      );
      await tester.pump();
      await polygon(tester);
      await tapButton(tester, 'confirm-exclusion');
      await tapButton(tester, 'apply-adjustments');
      expect(tester.takeException(), isNull);
    });
  }
}
