#!/usr/bin/env python3
"""YCam 风格自检（不需要 Mac / Xcode，只需要 numpy + Pillow）。

读取 Styles.swift 里的配方，用与 FilterEngine.swift 完全相同的数学做色彩计算，然后：
  1. 逐风格输出：相对“标准”的平均色差、灰阶偏色方向、是否过黄/过青
  2. 检查风格之间是否真的不同（FUJI 400 ≠ FUJI 青调，KODAK 800 ≠ KODAK 暖黄，…）
  3. 检查灰阶是否单调（没有色调反转）、是否大面积削波
  4. 生成合成场景的对比图 docs/style_contact_sheet.png 和报告 STYLE_CHECK_REPORT.md

重要：这只是“内部一致性与方向性”检查。它**不能**证明与真实胶片 / Apple 官方风格有 90% 相似度，
要证明这一点必须有同一场景的真实参考样张，再算 ΔE。阈值是我自己设的健康检查，不是标准。
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = (ROOT / "Styles.swift").read_text(encoding="utf-8")

IDENT = dict(exposure=0.0, contrast=0.0, saturation=1.0, vibrance=0.0, temperature=0.0, tint=0.0,
             shadowTint=(0.0, 0.0, 0.0), highlightTint=(0.0, 0.0, 0.0), midGamma=(1.0, 1.0, 1.0),
             blackLift=0.0, whiteRoll=0.0, mono=0.0, grain=0.0, bloom=0.0)
Y = np.array([0.2126, 0.7152, 0.0722])


def split_top(s):
    parts, depth, cur = [], 0, ""
    for ch in s:
        if ch == "(":
            depth += 1
        if ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur.strip())
    return parts


def parse_recipes():
    out = {}
    for m in re.finditer(r"case \.(\w+): return LookRecipe\((.*)\)\s*$", SRC, re.M):
        name, body = m.group(1), m.group(2)
        r = dict(IDENT)
        for part in split_top(body):
            k, v = [x.strip() for x in part.split(":", 1)]
            r[k] = tuple(float(x) for x in v[4:-1].split(",")) if v.startswith("rgb(") else float(v)
        out[name] = r
    return out


def titles():
    t = {}
    for m in re.finditer(r'case \.(\w+): return "([^"]+)"', SRC):
        t.setdefault(m.group(1), m.group(2))
    return t


def scaled(r, k):
    l = lambda v, i: i + (v - i) * k
    return dict(exposure=l(r["exposure"], 0), contrast=l(r["contrast"], 0), saturation=l(r["saturation"], 1),
                vibrance=l(r["vibrance"], 0), temperature=l(r["temperature"], 0), tint=l(r["tint"], 0),
                shadowTint=tuple(x * k for x in r["shadowTint"]),
                highlightTint=tuple(x * k for x in r["highlightTint"]),
                midGamma=tuple(l(x, 1) for x in r["midGamma"]), blackLift=l(r["blackLift"], 0),
                whiteRoll=l(r["whiteRoll"], 0), mono=l(r["mono"], 0), grain=r["grain"] * k, bloom=r["bloom"] * k)


def effective(r, point=(0.8, 0.5), intensity=1.0, exposure=0.0):
    """与 FilterEngine.effectiveRecipe 对应：横向 = 纯度（左灰 → 右纯），纵向 = 明度（上亮 → 下暗）。"""
    k = min(1.0, max(0.0, intensity))
    e = scaled(r, k)
    purity = max(0.0, min(1.25, point[0] / 0.8))
    e["temperature"] *= purity
    e["tint"] *= purity
    e["vibrance"] *= purity
    e["shadowTint"] = tuple(x * purity for x in e["shadowTint"])
    e["highlightTint"] = tuple(x * purity for x in e["highlightTint"])
    e["midGamma"] = tuple(1 + (x - 1) * purity for x in e["midGamma"])
    sat_mul = purity if purity <= 1 else 1 + (purity - 1) * 0.8
    e["saturation"] = max(0.0, e["saturation"]) * sat_mul
    tone = (0.5 - point[1]) * 2
    e["exposure"] += 0.6 * tone + exposure
    e["contrast"] -= 0.20 * tone
    return e


def to_linear(v):
    return np.where(v <= 0.04045, v / 12.92, np.power((np.maximum(v, 0) + 0.055) / 1.055, 2.4))


def to_gamma(v):
    return np.where(v <= 0.0031308, v * 12.92, 1.055 * np.power(np.maximum(v, 1e-12), 1 / 2.4) - 0.055)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def transform(rgb, p):
    """与 FilterEngine.transform 逐步对应（见 Swift 源码里的步骤编号）。"""
    rgb = np.clip(np.asarray(rgb, dtype=np.float64), 0, 1)
    lin = to_linear(rgb) * (2.0 ** p["exposure"])
    t, n = p["temperature"], p["tint"]
    w = np.array([1 + 0.22 * t + 0.03 * n, 1 - 0.12 * n + 0.02 * t, 1 - 0.28 * t + 0.03 * n])
    y0 = lin @ Y
    lin = lin * w
    y1 = lin @ Y
    k = np.where(y1 > 1e-6, y0 / np.maximum(y1, 1e-12), 1.0)
    lin = lin * k[:, None]
    g = to_gamma(np.clip(lin, 0, 1))
    g = np.power(g, np.array(p["midGamma"]))
    c = max(-1.0, min(1.0, p["contrast"]))
    g = g + c * (g * g * (3 - 2 * g) - g)
    l1 = g @ Y
    chroma = g.max(1) - g.min(1)
    sat = np.maximum(0, p["saturation"] * (1 + p["vibrance"] * (1 - chroma)))
    g = l1[:, None] + (g - l1[:, None]) * sat[:, None]
    l2 = np.clip(g, 0, 1) @ Y
    sw = 1 - smooth(0, 0.55, l2)
    hw = smooth(0.45, 1.0, l2)
    g = g + np.array(p["shadowTint"])[None, :] * sw[:, None] + np.array(p["highlightTint"])[None, :] * hw[:, None]
    g = np.clip(g, 0, 1)
    bl = p["blackLift"]
    g = bl + g * (1 - bl)
    wr = p["whiteRoll"]
    if wr != 0:
        q = np.clip((g - 0.6) / 0.4, 0, None)
        g = np.where(g > 0.6, g - wr * 0.25 * q * q, g)
    if p["mono"] > 0:
        l3 = g @ Y
        g = g + (l3[:, None] - g) * p["mono"]
    return np.clip(g, 0, 1)


M = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])
WHITE = np.array([0.95047, 1.0, 1.08883])


def lab(rgb):
    xyz = (to_linear(np.clip(rgb, 0, 1)) @ M.T) / WHITE
    f = np.where(xyz > 216 / 24389, np.cbrt(xyz), (24389 / 27 * xyz + 16) / 116)
    return np.stack([116 * f[:, 1] - 16, 500 * (f[:, 0] - f[:, 1]), 200 * (f[:, 1] - f[:, 2])], 1)


# ColorChecker 24 色的常用 sRGB 近似值（Wikipedia / X-Rite 公布值的取整，仅作相对比较）
CHECKER = np.array([
    (115, 82, 68), (194, 150, 130), (98, 122, 157), (87, 108, 67), (133, 128, 177), (103, 189, 170),
    (214, 126, 44), (80, 91, 166), (193, 90, 99), (94, 60, 108), (157, 188, 64), (224, 163, 46),
    (56, 61, 150), (70, 148, 73), (175, 54, 60), (231, 199, 31), (187, 86, 149), (8, 133, 161),
    (243, 243, 242), (200, 200, 200), (160, 160, 160), (122, 122, 121), (85, 85, 85), (52, 52, 52)],
    dtype=np.float64) / 255.0
NEUTRALS = CHECKER[19:23]            # 4 个中性灰块（不含最白、最黑）
RAMP = np.stack([np.linspace(0, 1, 33)] * 3, 1)

WARM = {"amber", "gold", "roseGold", "warm", "kodak800", "kodakWarmYellow"}
COOL = {"fuji400", "fujiCyan"}


def scene(w=360, h=240):
    img = np.zeros((h, w, 3))
    sky_h = int(h * 0.38)
    for y in range(sky_h):
        t = y / sky_h
        img[y, :] = (0.30 + 0.45 * t, 0.52 + 0.33 * t, 0.86 + 0.09 * t)
    img[sky_h:, :] = (0.78, 0.74, 0.67)                      # 墙
    img[sky_h:, : w // 3] = (0.27, 0.52, 0.19)               # 草 / 树叶
    yy, xx = np.mgrid[0:h, 0:w]
    face = ((xx - w * 0.55) ** 2 + (yy - h * 0.58) ** 2) < (h * 0.17) ** 2
    img[face] = (0.77, 0.58, 0.47)                           # 肤色
    cols = [(0.75, 0.21, 0.23), (0.88, 0.64, 0.18), (0.22, 0.27, 0.62), (0.03, 0.52, 0.63)]
    for i, c in enumerate(cols):
        x0 = int(w * 0.72) + (i % 2) * int(w * 0.13)
        y0 = sky_h + 8 + (i // 2) * 34
        img[y0:y0 + 28, x0:x0 + int(w * 0.12)] = c
    ramp_y = h - 22
    for x in range(w):
        img[ramp_y:, x] = x / (w - 1)
    return img


def main():
    recipes = parse_recipes()
    names = titles()
    order = list(recipes.keys())
    results, fails = {}, []
    base_lab = lab(CHECKER)
    eff = {k: effective(recipes[k]) for k in order}
    out_checker = {k: transform(CHECKER, eff[k]) for k in order}

    for k in order:
        oc = out_checker[k]
        d_e = np.sqrt(((lab(oc) - base_lab) ** 2).sum(1)).mean()
        nl = lab(transform(NEUTRALS, eff[k]))
        ramp_l = lab(transform(RAMP, eff[k]))[:, 0]
        mono_ok = bool(np.all(np.diff(ramp_l) >= -1e-6))
        ramp_out = transform(RAMP, eff[k])
        clip = float(((ramp_out <= 0.001) | (ramp_out >= 0.999)).all(1).mean())
        results[k] = dict(dE=float(d_e), a=float(nl[:, 1].mean()), b=float(nl[:, 2].mean()),
                          mono=mono_ok, clip=clip)

    def check(cond, msg):
        if not cond:
            fails.append(msg)
        return "PASS" if cond else "FAIL"

    lines = ["# YCam 风格自检报告（自动生成）", "",
             "> 范围：内部一致性 + 方向性检查（用与 Swift 相同的数学在 Python 里复算）。",
             "> **不是**与真实胶片 / Apple 官方风格的相似度证明，90% 目标没有被测得，见文末“未验证”。", "",
             "## 1. 每个风格相对“标准”的变化（ColorChecker 24 色近似值，ΔE76）", "",
             "| 风格 | 平均ΔE | 中性灰 a* | 中性灰 b* | 灰阶单调 | 灰阶削波 |", "|---|---|---|---|---|---|"]
    for k in order:
        r = results[k]
        lines.append(f"| {names.get(k, k)} | {r['dE']:.1f} | {r['a']:+.1f} | {r['b']:+.1f} | "
                     f"{'是' if r['mono'] else '否'} | {r['clip'] * 100:.0f}% |")
        check(r["mono"], f"{k}: 灰阶不单调")
    lines += ["", "## 2. 名称与方向是否一致（阈值为本项目自设）", "", "| 检查 | 结果 | 说明 |", "|---|---|---|"]

    for k in sorted(WARM):
        if k == "roseGold":
            res = check(results[k]["a"] > 0.3, "roseGold 应偏品红/粉(a*>0)")
            lines.append(f"| {names[k]} 偏粉 | {res} | 中性灰 a*={results[k]['a']:+.1f} |")
        else:
            res = check(results[k]["b"] > 1.0, f"{k} 应偏暖(b*>0)")
            lines.append(f"| {names[k]} 偏暖 | {res} | 中性灰 b*={results[k]['b']:+.1f} |")
    yb = results["kodakWarmYellow"]["b"]
    res = check(yb < 14.0, "kodakWarmYellow 过黄")
    lines.append(f"| KODAK 暖黄 不过黄（b*<14） | {res} | b*={yb:+.1f} |")
    res = check(results["fujiCyan"]["a"] < -1.0 and results["fujiCyan"]["b"] < -1.0,
                "fujiCyan 应同时偏青绿(a*<0)与偏蓝(b*<0)")
    lines.append(f"| FUJI 青调 偏青（a*<0 且 b*<0） | {res} | a*={results['fujiCyan']['a']:+.1f}, b*={results['fujiCyan']['b']:+.1f} |")
    res = check(results["fuji400"]["b"] < 0.0, "fuji400 应略偏冷(b*<0)")
    lines.append(f"| FUJI 400 略偏冷（b*<0） | {res} | b*={results['fuji400']['b']:+.1f} |")
    res = check(results["kodak800"]["b"] > 1.0, "kodak800 应偏暖")
    lines.append(f"| KODAK 800 偏暖（b*>1） | {res} | b*={results['kodak800']['b']:+.1f} |")
    res = check(results["coolRose"]["b"] < -1.0 and results["coolRose"]["a"] > 0.3, "coolRose 应偏冷偏粉")
    lines.append(f"| 冷调玫瑰色 偏冷偏粉（b*<-1 且 a*>0） | {res} | a*={results['coolRose']['a']:+.1f}, b*={results['coolRose']['b']:+.1f} |")
    res = check(results["monochrome"]["a"] ** 2 + results["monochrome"]["b"] ** 2 < 1.0, "monochrome 灰阶应无色")
    lines.append(f"| 黑白 灰阶无色 | {res} | a*={results['monochrome']['a']:+.1f}, b*={results['monochrome']['b']:+.1f} |")

    # 色调板“使用公式”：左灰 / 右纯、上亮 / 下暗
    amber = recipes["amber"]
    def chroma(point):
        out = lab(transform(CHECKER, effective(amber, point=point)))
        return float(np.sqrt(out[:, 1] ** 2 + out[:, 2] ** 2).mean())
    def lightness(point):
        return float(lab(transform(CHECKER, effective(amber, point=point)))[:, 0].mean())
    lines += ["", "## 2b. 色调板公式（按你给的“调色盘使用公式”，以琥珀色为例）", "", "| 检查 | 结果 | 数值 |", "|---|---|---|"]
    res = check(chroma((0.0, 0.5)) < 3.0, "色调板最左边应是灰（低纯度）")
    lines.append(f"| 最左边 = 灰（平均彩度 < 3） | {res} | C*={chroma((0.0, 0.5)):.1f} |")
    res = check(chroma((1.0, 0.5)) > chroma((0.8, 0.5)) > chroma((0.4, 0.5)), "纯度应随横向增加")
    lines.append(f"| 越往右越纯 | {res} | C*(0.4/0.8/1.0)={chroma((0.4, 0.5)):.1f} / {chroma((0.8, 0.5)):.1f} / {chroma((1.0, 0.5)):.1f} |")
    res = check(lightness((0.8, 0.0)) > lightness((0.8, 0.5)) > lightness((0.8, 1.0)), "明度应随纵向向下变暗")
    lines.append(f"| 越往上越亮、越往下越暗 | {res} | L*(上/中/下)={lightness((0.8, 0.0)):.1f} / {lightness((0.8, 0.5)):.1f} / {lightness((0.8, 1.0)):.1f} |")

    lines += ["", "## 3. 风格之间是否真的不同（两两平均 ΔE76；阈值 ≥ 4）", "", "| 对比 | ΔE | 结果 |", "|---|---|---|"]
    pairs = [("fuji400", "fujiCyan"), ("kodak800", "kodakWarmYellow"), ("fuji400", "kodak800"),
             ("fujiCyan", "kodakWarmYellow"), ("pearl", "fuji400"), ("pearl", "kodak800"), ("amber", "gold")]
    for a_, b_ in pairs:
        d = np.sqrt(((lab(out_checker[a_]) - lab(out_checker[b_])) ** 2).sum(1)).mean()
        res = check(d >= 4.0, f"{a_} 与 {b_} 过于相似 (ΔE={d:.1f})")
        lines.append(f"| {names[a_]} vs {names[b_]} | {d:.1f} | {res} |")

    lines += ["", "## 4. 自检结论", ""]
    lines.append("全部通过" if not fails else "未通过项：" + "；".join(fails))
    lines += ["", "## 5. 没有被验证的部分（必须明确）", "",
              "- **与真实 FUJI 400 / KODAK 800 / Apple 摄影风格 / Pearl 的 90% 相似度：没有测量。** "
              "需要同一场景的真实参考样张（例如同一张 RAW 用目标胶片 / 风格处理后的成品），再用 ΔE 拟合配方。",
              "- 柔光 / 柔焦（珠光）、胶片颗粒、人像光效和景深是 Core Image / Vision 滤镜，这里只复算了颜色部分，没有复算它们。",
              "- ColorChecker 数值是常见近似值，显示设备与真实光照也会影响观感。",
              "- 没有找到可验证的 Pearl 开源实现，Pearl 是按“柔和、低对比、微粉青高光”自行设计的。"]
    (ROOT / "STYLE_CHECK_REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    # 对比图
    sc = scene()
    h, w, _ = sc.shape
    cols, tile_h = 4, h + 20
    rows = (len(order) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w, rows * tile_h), (20, 20, 20))
    draw = ImageDraw.Draw(sheet)
    flat = sc.reshape(-1, 3)
    for i, k in enumerate(order):
        out = transform(flat, eff[k]).reshape(h, w, 3)
        tile = Image.fromarray((out * 255 + 0.5).astype(np.uint8))
        x, y = (i % cols) * w, (i // cols) * tile_h
        sheet.paste(tile, (x, y + 20))
        draw.text((x + 6, y + 4), f"{k}  dE={results[k]['dE']:.1f}", fill=(255, 255, 255))
    sheet.save(ROOT / "docs" / "style_contact_sheet.png")

    print("\n".join(lines))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
