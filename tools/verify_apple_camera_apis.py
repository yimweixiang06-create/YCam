#!/usr/bin/env python3
"""Apple capture API regression checks; not an Apple color certification."""
from pathlib import Path
root=Path(__file__).resolve().parent.parent
m=(root/"CameraModel.swift").read_text()
styles=(root/"Styles.swift").read_text()
glass=(root/"Glass.swift").read_text()
checks=[
".workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!",
".outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!",
"let colorSpace = decoded.colorSpace ?? Self.sRGB",
"ciContext.createCGImage(output, from: source.extent, format: .RGBA8, colorSpace: colorSpace)",
"CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, Self.sRGB, .shouldPropagate)",
"kCVPixelBufferMetalCompatibilityKey as String: true",
"private func restoreAutomaticCaptureModes(_ device: AVCaptureDevice)",
"device.isExposureModeSupported(.continuousAutoExposure)",
"device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance)",
"if !manualShutter, device.isExposurePointOfInterestSupported {",
"videoOutput.alwaysDiscardsLateVideoFrames = true",
"adaptivePreviewLongEdge = max(560, adaptivePreviewLongEdge * 0.82)",
"let list = device.activeFormat.supportedMaxPhotoDimensions",
"settings.photoQualityPrioritization = .quality",
"photoOutput.maxPhotoQualityPrioritization = .quality"
]
for code in checks: assert code in m, code
assert m.count("restoreAutomaticCaptureModes(device)") >= 4
assert "if shutterSeconds == nil," in m and "if whiteBalanceKelvin == nil," in m
assert "glassEffect" in glass and "case .pearl: return LookRecipe(" in styles
print("PASS: color-space contract, output profile, adaptive AE/AWB, continuous tap exposure, existing photo quality & preview guards")
