#!/usr/bin/env python3
"""Regressions: max-resolution photo, native-position controls and no duplicate portrait/zoom overlays."""
from pathlib import Path
root = Path(__file__).resolve().parent.parent
model = (root / "CameraModel.swift").read_text(encoding="utf-8")
home = (root / "CameraHomeView.swift").read_text(encoding="utf-8")
panel = (root / "ControlPanels.swift").read_text(encoding="utf-8")
ctrl = (root / "CameraControls.swift").read_text(encoding="utf-8")

# Photos always request the device's available maximum; no max/half choice.
assert "PhotoResolutionChoice" not in "\n".join((model, home, panel, ctrl))
assert "halfPhotoDims" not in model and "maximumPhotoTitle" in model
assert "supportedMaxPhotoDimensions" in model
assert "settings.maxPhotoDimensions = maxPhotoDims" in model

# Only pinch gesture zoom remains: no second floating 1x/2x strip.
assert "ZoomPills(" not in home and "struct ZoomPills" not in panel
assert "onPinchChanged" in home and "camera.setZoom" in home

# Portrait lighting's previous hexagon/circle selector was deleted entirely.
assert "PortraitLightingStrip" not in home
assert "lightingStrip(m)" not in home
assert 'Image(systemName: item == items[nearest] ? "hexagon.fill" : "hexagon")' not in home

# Pinning top controls must not shrink or relocate the camera preview.
assert "m.vfTop(pinned: false)" in home
assert "PinnedRow(items: layout.pinned" in home

# Each mode label must be a working Button; a zero-distance whole-row drag steals taps.
assert "private struct CaptureModeStrip: View" in home
assert "ForEach(modes) { mode in" in home
assert "Button {" in home.split("private struct CaptureModeStrip: View", 1)[1]
assert "DragGesture(minimumDistance: 12 * m.s" in home
assert ".simultaneousGesture(" in home
assert "DragGesture(minimumDistance: 0).onEnded" not in home
# Fixed-size bottom mode bar; frosted, not glossy controls.
assert ".legacyPressScale" not in home and "modeDragging" not in home
assert ".frostedPanel(Capsule())" in home
assert "无需选择，始终请求最高分辨率" in panel
assert "recordingBadge" in home and "camera.isRecording" in home
print("PASS: max-only photos; pinch zoom; no old lighting overlay; fixed mode bar with working taps and swipes; top controls do not resize preview")
