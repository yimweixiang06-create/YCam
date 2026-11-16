#!/usr/bin/env python3
"""Compare all 10 YCam named photo filters on an internal color chart.

Relative difference is NOT Apple accuracy. Never use this synthetic check
to justify claims about proprietary Apple processing or ΔE to Apple references.
"""
import re
from pathlib import Path
import numpy as np
import style_check as sc

src = (Path(__file__).resolve().parent.parent / "Styles.swift").read_text(encoding="utf-8")
block = src.split("enum AppleFilter:", 1)[1].split("// MARK: - 界面上的全部风格状态", 1)[0]
expected = ["original", "vivid", "vividWarm", "vividCool", "dramatic",
            "dramaticWarm", "dramaticCool", "mono", "silvertone", "noir"]
recipes = {}
for name, body in re.findall(r"case [.]([A-Za-z0-9_]+): return LookRecipe[(](.*)[)]$", block, re.M):
    p = dict(sc.IDENT)
    for part in sc.split_top(body):
        key, value = (x.strip() for x in part.split(":", 1))
        p[key] = (tuple(float(x) for x in value[4:-1].split(","))
                  if value.startswith("rgb(") else float(value))
    recipes[name] = p
assert set(recipes) == set(expected), (set(expected) - set(recipes), set(recipes) - set(expected))
lab = {name: sc.lab(sc.transform(sc.CHECKER, p)) for name, p in recipes.items()}
results = []
for i, name in enumerate(expected):
    for other in expected[i+1:]:
        delta = float(np.sqrt(((lab[name] - lab[other]) ** 2).sum(axis=1)).mean())
        results.append((delta, name, other))
results.sort()
# Guards against accidentally sharing one identical filter recipe. This is
# not a subjective quality score and does not certify visible uniqueness.
assert results[0][0] >= 0.65, f"Filters too similar: {results[:5]}"
assert np.allclose(sc.transform(sc.CHECKER, recipes["original"]), sc.CHECKER, atol=2e-5)
print(f"PASS: {len(recipes)} named filters; {len(results)} distinct pairs; weakest synthetic mean ΔE76={results[0][0]:.2f} ({results[0][1]} vs {results[0][2]})")
