# -*- coding: utf-8 -*-
"""PC 재현용 ONNX 추론 서버 — test/field_replay_test.dart 가 띄운다.

앱의 Dart 분석 코드(전처리·구제 경로·디코더·수고봉 해·계측)는 그대로 돌리고
추론만 이 프로세스가 앱과 같은 .onnx 파일로 대신한다.

프로토콜(한 줄씩): stdin  "<asset>\t<입력 float32 파일>\t<size>"
                  stdout "<출력파일1>:<d0,d1,...>;<출력파일2>:<...>"  (float32 원시값)
"""
import os
import sys

import numpy as np
import onnxruntime as ort

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_sessions = {}


def session(asset):
    s = _sessions.get(asset)
    if s is None:
        s = ort.InferenceSession(os.path.join(ROOT, asset),
                                 providers=['CPUExecutionProvider'])
        _sessions[asset] = s
    return s


def main():
    for line in sys.stdin:
        line = line.rstrip('\r\n')
        if not line:
            continue
        asset, in_path, size = line.split('\t')
        size = int(size)
        x = np.fromfile(in_path, dtype=np.float32).reshape(1, 3, size, size)
        s = session(asset)
        outs = s.run(None, {s.get_inputs()[0].name: x})
        parts = []
        for i, o in enumerate(outs):
            p = f'{in_path}.out{i}'
            np.ascontiguousarray(o, dtype=np.float32).tofile(p)
            parts.append(f"{p}:{','.join(str(d) for d in o.shape)}")
        sys.stdout.write(';'.join(parts) + '\n')
        sys.stdout.flush()


if __name__ == '__main__':
    main()
