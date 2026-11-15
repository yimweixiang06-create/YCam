#!/usr/bin/env python3
"""User regression tests: max-only, no second zoom bar, stable mode bar, responsive lighting."""
from pathlib import Path
root = Path(__file__).resolve().parent.parent
model = (root / 'CameraModel.swift').read_text()
home = (root / 'CameraHomeView.swift').read_text()
panel = (root / 'ControlPanels.swift').read_text()
ctrl = (root / 'CameraControls.swift').read_text()
assert 'PhotoResolutionChoice' not in '\n'.join((model,home,panel,ctrl))
assert 'halfPhotoDims' not in model and 'maximumPhotoTitle' in model
assert 'supportedMaxPhotoDimensions' in model and 'settings.maxPhotoDimensions = maxPhotoDims' in model
assert 'ZoomPills(' not in home and 'struct ZoomPills' not in panel
assert 'onPinchChanged' in home and 'camera.setZoom' in home
assert 'PortraitLightingStrip' in home and '@GestureState private var translation:' in home
assert 'Image(systemName: item == items[nearest] ? "hexagon.fill" : "hexagon")' not in home
assert 'value.translation.width' in home and 'if newIndex != current { onSelect(allLights[newIndex]) }' in home
assert '.legacyPressScale' not in home and 'modeDragging' not in home
assert '.frostedPanel(Capsule())' in home
assert '无需选择，始终请求最高分辨率' in panel
print('PASS: max-only photos; pinch zoom; no floating zoom pill; fixed mode strip; native-style low-profile portrait-lighting dial')
