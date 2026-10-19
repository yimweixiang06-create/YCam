#!/usr/bin/env python3
"""静态检查（没有 Xcode 时能做的事）：括号配对、符号交叉引用、LookRecipe 参数顺序、Liquid Glass 官方 API 使用规范。
注意：这不是编译。真正的编译只会在 GitHub Actions 的 Xcode 26 上发生。"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = sorted(ROOT.glob("*.swift"))
text = {p.name: p.read_text(encoding="utf-8") for p in SWIFT}
problems, notes = [], []


def strip(src):
    # 先去字符串（里面可能有 "//"，例如 "photos-redirect://"），再去注释
    src = re.sub(r'"(?:\\.|[^"\\])*"', '""', src)
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"//.*", "", src)


# 1. 括号配对
for name, src in text.items():
    s = strip(src)
    for a, b in ("()", "[]", "{}"):
        if s.count(a) != s.count(b):
            problems.append(f"{name}: {a}{b} 不配对 ({s.count(a)} vs {s.count(b)})")
notes.append(f"括号配对检查：{len(text)} 个 Swift 文件")

# 2. CameraStyle：title / swatch / recipe 三个 switch 都覆盖全部 case
st = text["Styles.swift"]
cases = re.findall(r"case (\w+(?:, \w+)*)\n", re.search(r"enum CameraStyle.*?var id", st, re.S).group(0))
all_cases = [c.strip() for line in cases for c in line.split(",")]
for prop in ("title", "swatch", "recipe"):
    block = re.search(r"var %s: \w+ \{(.*?)\n    \}" % prop, st, re.S).group(1)
    got = set(re.findall(r"case \.(\w+):", block))
    if got != set(all_cases):
        problems.append(f"CameraStyle.{prop} 缺少/多余 case：{set(all_cases) ^ got}")
notes.append(f"CameraStyle 共 {len(all_cases)} 个风格，title/swatch/recipe 全部覆盖")

# 3. LookRecipe(...) 参数必须按声明顺序（成员初始化器要求）
decl = re.findall(r"^    var (\w+)\b", re.search(r"struct LookRecipe.*?func scaled", st, re.S).group(0), re.M)
for m in re.finditer(r"case \.(\w+): return LookRecipe\((.*)\)\s*$", st, re.M):
    labels = re.findall(r"(?:^|, )(\w+):", re.sub(r"rgb\([^)]*\)", "X", m.group(2)))
    idx = [decl.index(l) for l in labels]
    if idx != sorted(idx):
        problems.append(f"{m.group(1)}: LookRecipe 参数顺序与声明顺序不一致 {labels}")
notes.append("LookRecipe 参数顺序检查完成")

# 4. 视图里用到的 camera.xxx / FilterEngine.shared.xxx 必须真实存在且不是 private
model = text["CameraModel.swift"]
declared, private_names = set(), set()
for line in model.splitlines():
    m = re.match(r"\s*(?:@Published\s+)?(private(?:\(set\))?\s+)?(?:static\s+)?(?:@MainActor\s+)?(?:func|var|let)\s+(\w+)", line)
    if m:
        declared.add(m.group(2))
        if m.group(1) and "(set)" not in m.group(1):
            private_names.add(m.group(2))
used = set()
for name in ("CameraHomeView.swift", "CameraPreview.swift"):
    used |= set(re.findall(r"\$?camera\.(\w+)", strip(text[name])))
for u in sorted(used):
    if u not in declared:
        problems.append(f"视图使用了不存在的 camera.{u}")
    elif u in private_names:
        problems.append(f"视图使用了 private 成员 camera.{u}")
engine_declared = set(re.findall(r"func (\w+)\(", text["FilterEngine.swift"]))
for name, src in text.items():
    for u in set(re.findall(r"FilterEngine\.shared\.(\w+)", src)):
        if u not in engine_declared:
            problems.append(f"{name}: FilterEngine.shared.{u} 不存在")
notes.append(f"交叉引用：视图使用了 {len(used)} 个 camera 成员，全部存在")

# 5. 旧实现不应残留
for name, src in text.items():
    for bad in ("NativeStyle", "FilmPreset", "ImageLook", "glassBackground", "AVCaptureVideoPreviewLayer",
                "AVCaptureMovieFileOutput", "CITemperatureAndTint"):
        if bad in strip(src):
            problems.append(f"{name}: 仍包含旧实现 {bad}")

# 6. Liquid Glass 官方性
glass = text["Glass.swift"]
for needle in ("glassEffect(", "Glass.regular", ".interactive()", "GlassEffectContainer(", "glassEffectID(",
               "#available(iOS 26.0, *)", "#if compiler(>=6.2)"):
    if needle not in glass:
        problems.append(f"Glass.swift 缺少官方 API/保护：{needle}")
material = re.compile(r"\.(?:ultraThinMaterial|thinMaterial|regularMaterial|thickMaterial|ultraThickMaterial)|UIBlurEffect|UIVisualEffectView|\bMaterial\b")
for name, src in text.items():
    code = strip(src)
    if name != "Glass.swift" and (".glassEffect(" in code or "GlassEffectContainer(" in code or ".glassEffectID(" in code):
        problems.append(f"{name}: 绕过封装直接调用官方玻璃 API（应统一走 Glass.swift）")
    if name != "Glass.swift" and material.search(code):
        problems.append(f"{name}: 出现自制模糊/Material（不是官方 Liquid Glass）")
legacy_block = re.search(r"// BEGIN LEGACY.*?// END LEGACY", glass, re.S)
if not legacy_block:
    problems.append("Glass.swift: 缺少 BEGIN/END LEGACY 标记")
else:
    outside = glass.replace(legacy_block.group(0), "")
    if material.search(strip(outside)):
        problems.append("Glass.swift: Material 只允许出现在 iOS 18–25 的 LEGACY 磨砂降级区块里")
for name, src in text.items():
    if name != "Glass.swift" and ".buttonStyle(.plain)" in strip(src):
        problems.append(f"{name}: 玻璃按钮应使用 GlassButtonStyle（带 iOS 18–25 的按压反馈）")
plist = (ROOT / "Info.plist").read_text(encoding="utf-8")
if "UIDesignRequiresCompatibility" in plist:
    problems.append("Info.plist 含 UIDesignRequiresCompatibility（会关闭 Liquid Glass）")
usage = {n: len(re.findall(r"\.glassSurface\(", s)) for n, s in text.items() if ".glassSurface(" in s}
inter = {n: len(re.findall(r"interactive: true", s)) for n, s in text.items() if "interactive: true" in s}
notes.append(f"glassSurface 使用次数：{usage}")
notes.append(f"interactive(触摸/拖动反馈) 使用次数：{inter}")
groups = {n: s.count("GlassGroup(") for n, s in text.items() if "GlassGroup(" in s}
morphs = {n: s.count("GlassMorph(") for n, s in text.items() if "GlassMorph(" in s}
notes.append(f"GlassGroup(官方 GlassEffectContainer) 使用：{groups}")
notes.append(f"GlassMorph(iOS26 官方 glassEffectID 形变 / iOS18 matchedGeometry 近似)：{morphs}")

print("\n".join("· " + n for n in notes))
if problems:
    print("\n未通过：")
    print("\n".join("✗ " + p for p in problems))
    sys.exit(1)
print("\n全部静态检查通过（注意：这不是编译）")
