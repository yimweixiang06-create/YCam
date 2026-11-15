#!/usr/bin/env python3
"""把 .cube（3D LUT，33x33x33）转成 App 里用的 Asset Catalog 数据集（UInt16 RGB，红色变化最快）。

用法：python3 tools/cube_to_asset.py 文件1.cube 文件2.cube ...
数据集名字 = LUT_<名字>，名字在下面的 NAMES 里按文件名前缀匹配。
"""
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
NAMES = {  # 文件名前缀 -> App 里的名字（Styles.swift 的 lutName 要和这里一致）
    "PROVIA": "PROVIA", "Velvia": "VELVIA", "ASTIA": "ASTIA", "REALA-ACE": "REALA",
    "CC": "CC", "CN": "CN", "PRO-Neg": "PRONEG", "ETERNA-BB": "ETERNABB", "ETERNA": "ETERNA",
}
SIZE = 33


def read_cube(path: Path) -> np.ndarray:
    size, rows, dmin, dmax = None, [], (0.0, 0.0, 0.0), (1.0, 1.0, 1.0)
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("TITLE"):
            continue
        if line.startswith("LUT_3D_SIZE"):
            size = int(line.split()[1])
        elif line.startswith("DOMAIN_MIN"):
            dmin = tuple(float(x) for x in line.split()[1:4])
        elif line.startswith("DOMAIN_MAX"):
            dmax = tuple(float(x) for x in line.split()[1:4])
        elif line[0] in "0123456789-.+":
            rows.append([float(x) for x in line.split()[:3]])
    assert size == SIZE, f"{path.name}: LUT_3D_SIZE={size}（需要 {SIZE}）"
    assert dmin == (0.0, 0.0, 0.0) and dmax == (1.0, 1.0, 1.0), f"{path.name}: DOMAIN 不是 0..1"
    arr = np.array(rows, dtype=np.float64)
    assert arr.shape == (SIZE ** 3, 3), f"{path.name}: 数据行数 {arr.shape}"
    return np.clip(arr, 0.0, 1.0)


def main(files):
    for f in files:
        p = Path(f)
        stem = p.stem.replace("-HAKv03", "")
        name = NAMES.get(stem)
        assert name, f"不认识的文件名：{p.name}"
        data = np.round(read_cube(p) * 65535).astype("<u2").tobytes()
        folder = ROOT / "Assets.xcassets" / f"LUT_{name}.dataset"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{name}.bin").write_bytes(data)
        (folder / "Contents.json").write_text(json.dumps({
            "data": [{"filename": f"{name}.bin", "idiom": "universal", "universal-type-identifier": "public.data"}],
            "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
        print(f"{p.name} -> LUT_{name}.dataset ({len(data)} 字节)")


if __name__ == "__main__":
    main(sys.argv[1:])
