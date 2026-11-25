import 'dart:convert';

import 'package:bsi_field/src/models/draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restores an earlier draft with the bundled FP32 model', () {
    final saved = SurveyDraft()
      ..treeId = '013'
      ..dbhCm = 35;
    final oldJson = saved.toJson();
    oldJson['modelAsset'] = 'assets/models/bsi_seg_yolo26s_640.onnx';

    final restored = SurveyDraft.fromJsonString(jsonEncode(oldJson));

    expect(restored?.modelAsset, SurveyDraft.defaultModelAsset);
    expect(restored?.modelAsset, endsWith('.param'));
    expect(restored?.treeId, '013');
    expect(restored?.dbhCm, 35);
  });
}
