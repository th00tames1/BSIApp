"""Run the bundled FP32 ncnn graphs on a desktop for the Dart photo replays."""

from pathlib import Path
import sys

import ncnn
import numpy as np


ROOT = Path(__file__).resolve().parent.parent
sessions = {}


def session(asset):
    if asset not in sessions:
        graph = ROOT / asset
        net = ncnn.Net()
        net.opt.num_threads = 4
        net.opt.use_vulkan_compute = False
        net.opt.use_fp16_packed = False
        net.opt.use_fp16_storage = False
        net.opt.use_fp16_arithmetic = False
        net.opt.use_bf16_packed = False
        net.opt.use_bf16_storage = False
        net.opt.use_int8_inference = False
        if net.load_param(str(graph)) or net.load_model(str(graph.with_suffix(".bin"))):
            raise RuntimeError(f"Could not load {asset}")
        sessions[asset] = net
    return sessions[asset]


def rank_detections(head):
    """Two-stage TopK used by the original YOLO26 models and the mobile bridge."""
    scores = head[:, 4:6]
    anchors = np.argsort(-np.max(scores, axis=1), kind="stable")[:300]
    best = np.argsort(-scores[anchors].ravel(), kind="stable")[:300]
    classes = best % 2
    candidates = head[anchors[best // 2]]
    ranked = np.column_stack((
        candidates[:, :4],
        candidates[np.arange(300), 4 + classes],
        classes.astype(np.float32),
        candidates[:, 6:],
    ))
    return ranked


def run(asset, values):
    stem = Path(asset).stem
    extractor = session(asset).create_extractor()
    if extractor.input("in0", ncnn.Mat(values)):
        raise RuntimeError(f"Could not set input for {asset}")
    pole = stem == "pole_boundary_640"
    outputs = []
    for name in ("out0",) if pole else ("out0", "out1"):
        code, tensor = extractor.extract(name)
        if code:
            raise RuntimeError(f"Could not read {name} for {asset}: {code}")
        outputs.append(np.array(tensor, dtype=np.float32, copy=True))
    outputs[0] = rank_detections(outputs[0])
    return [np.expand_dims(value, 0) for value in outputs]


def main():
    for line in sys.stdin:
        asset, raw_path, size = line.rstrip("\r\n").split("\t")
        if size != "640":
            raise ValueError(f"Expected 640 x 640 inputs, got {size}")
        values = np.fromfile(raw_path, dtype=np.float32).reshape(3, 640, 640)
        parts = []
        for index, output in enumerate(run(asset, values)):
            destination = f"{raw_path}.out{index}"
            output.tofile(destination)
            shape = ",".join(map(str, output.shape))
            parts.append(f"{destination}:{shape}")
        print(";".join(parts), flush=True)


if __name__ == "__main__":
    main()
