import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models/survey.dart';
import '../theme.dart';

/// 촬영하지 못한 방위를 야장 값으로 채우는 입력창.
///
/// BSI = Σ 방위별 (그을음 최고 높이 × 그을음 면적비) 이므로 이 두 값만 있으면
/// 그 방위가 합에 들어간다. 나머지 계측치는 사진이 있어야 나오는 값이라 비워 둔다.
///
/// 반환: 저장하면 [AzimuthResult](manual: true), 지우면 [_removed], 취소면 null.
Future<Object?> showManualFaceSheet(
  BuildContext context,
  Azimuth az,
  AzimuthResult? existing,
) =>
    showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ManualFaceSheet(az: az, existing: existing),
    );

/// 입력을 지웠다는 신호(null은 "취소"라 구분이 필요하다).
const removedManualFace = Object();

class _ManualFaceSheet extends StatefulWidget {
  final Azimuth az;
  final AzimuthResult? existing;
  const _ManualFaceSheet({required this.az, required this.existing});
  @override
  State<_ManualFaceSheet> createState() => _ManualFaceSheetState();
}

class _ManualFaceSheetState extends State<_ManualFaceSheet> {
  late final TextEditingController _h =
      TextEditingController(text: _fmt(widget.existing?.sootHeightM));
  late final TextEditingController _r =
      TextEditingController(text: _fmt(_ratioPct(widget.existing?.sootProportion)));
  String? _err;

  /// 사진이 있는 면을 고치는 중인지(값만 덮어쓴다).
  bool get _hasPhoto => widget.existing?.imagePath != null;

  static double? _ratioPct(double? v) => (v == null || v.isNaN) ? null : v * 100;

  /// 저장된 값을 손실 없이 되돌려준다. 프리필이 반올림되면 값을 고치지 않고
  /// 저장만 눌러도 기록이 조용히 바뀐다.
  static String _fmt(double? v) {
    if (v == null || v.isNaN) return '';
    final s = v.toStringAsFixed(2); // 부동소수 잡음 제거
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
  }

  @override
  void dispose() {
    _h.dispose();
    _r.dispose();
    super.dispose();
  }

  void _save() {
    final h = double.tryParse(_h.text.trim());
    final rPct = double.tryParse(_r.text.trim());
    if (h == null || rPct == null) {
      setState(() => _err = tr('두 값을 모두 숫자로 입력하세요', 'Enter both values as numbers'));
      return;
    }
    if (h <= 0) {
      setState(() => _err = tr('그을음 높이는 0보다 커야 합니다', 'Char height must be > 0'));
      return;
    }
    if (rPct < 0 || rPct > 100) {
      setState(() => _err = tr('그을음 면적비는 0 ~ 100 % 입니다', 'Char ratio must be 0-100%'));
      return;
    }
    final base = widget.existing;
    if (base != null && base.imagePath != null) {
      // 사진이 있는 면을 손으로 고치는 경우 — 사진·오버레이·스케일은 그대로 두고
      // BSI에 들어가는 두 값만 조사자 값으로 덮는다(출처는 'edited'로 남는다).
      Navigator.pop(
        context,
        base.copyWith(
          sootHeightM: h,
          sootProportion: rPct / 100,
          analysed: true,
          manualEdited: true,
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      AzimuthResult(
        azimuth: widget.az.code,
        sootHeightM: h,
        sootProportion: rPct / 100,
        analysed: true, // BSI 합에 들어가야 하므로
        manual: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      // 키보드가 올라와도 입력칸이 가리지 않게.
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.edit_note, size: 20, color: p.navy),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                _hasPhoto
                    ? tr('${widget.az.label} 값 수정', 'Edit ${widget.az.label}')
                    : tr('${widget.az.label} 직접 입력',
                        'Enter ${widget.az.label} manually'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
              _hasPhoto
                  ? tr('분석값 대신 조사자 값이 BSI 합에 들어갑니다. 사진과 오버레이는 그대로 남습니다.',
                      'Your values replace the analysed ones in the BSI sum; the photo and overlay are kept.')
                  : tr('사진을 찍지 못한 방위를 야장 값으로 채웁니다. 두 값이 그대로 BSI 합에 들어갑니다.',
                      'Fill an un-photographed aspect from your field notes. '
                          'Both values feed the BSI sum directly.'),
              style: TextStyle(fontSize: 12, height: 1.45, color: p.muted)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _h,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: tr('그을음 최고 높이', 'Max char height'),
            suffixText: 'm',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _r,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: tr('그을음 면적비', 'Char area ratio'),
            suffixText: '%',
          ),
        ),
        if (_err != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_err!, style: TextStyle(fontSize: 12, color: p.danger)),
          ),
        ],
        const SizedBox(height: 18),
        Row(children: [
          if (widget.existing != null && !_hasPhoto)
            TextButton(
              onPressed: () => Navigator.pop(context, removedManualFace),
              child: Text(tr('입력 지우기', 'Clear'),
                  style: TextStyle(color: p.danger)),
            ),
          const Spacer(),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('취소', 'Cancel'))),
          const SizedBox(width: 4),
          FilledButton(onPressed: _save, child: Text(tr('저장', 'Save'))),
        ]),
      ]),
    );
  }
}
