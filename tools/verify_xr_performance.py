#!/usr/bin/env python3
"""Source invariants for iPhone XR / iOS 18 and newer YCam builds.

These checks guard real-time pipeline and platform compatibility decisions.
They are NOT FPS benchmarks, device profiling or security certification.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def source(name):
    return (ROOT / name).read_text(encoding="utf-8")

model = source("CameraModel.swift")
home = source("CameraHomeView.swift")
recorder = source("VideoRecorder.swift")
styles = source("Styles.swift")
glass = source("Glass.swift")
plist = source("Info.plist")
project = source("YCam.xcodeproj/project.pbxproj")

assert "IPHONEOS_DEPLOYMENT_TARGET = 18.0;" in project
assert "#available(iOS 26.0, *)" in glass
assert "legacy(content)" in glass and "Material.regular" in glass
for name in (
    "NSCameraUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSPhotoLibraryAddUsageDescription",
):
    assert f"<key>{name}</key>" in plist, name

# Pulling Control Center to start screen recording must not be treated like
# permanently backgrounding the camera.
assert "case .inactive:" in home
assert "case .background:" in home
assert "camera.sceneWillResignActive()" in home

# Exactly one photo style or film recipe per style; visual cards are immutable.
assert "private static let cardColorCache:" in styles
assert "var cardColors: [Color] { Self.cardColorCache[self] ?? [] }" in styles
assert "private func makeCardColors() -> [Color]" in styles
assert "onBack: { go(.styles, fromStyleBack: true) }" in home

# Never trade away actual selected recording resolution for an idle preview.
assert "let fullResolutionForRecording = dataIsVideoMode && recorder.isArmed" in model
assert "let scale = fullResolutionForRecording ? 1" in model
assert "recorder.appendVideo(target, pts: pts)" in model
assert "videoOutput.alwaysDiscardsLateVideoFrames = true" in model
assert "captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer:" in model
assert "kCVPixelBufferPoolAllocationThresholdKey as String" in model
assert "CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(" in model
assert "recorder.previewFrameStride" in model
assert "isReadyForMoreMediaData ?? true" in model
assert "var previewFrameStride: Int { previewStride }" in recorder
assert "func noteVideoProcessingTime(milliseconds: Double)" in recorder
assert "recorder.noteVideoProcessingTime(milliseconds:" in model
assert "writerBackpressureDrops" in recorder
assert "CMTimeAdd(lastVideoPTS, frameDuration)" in recorder

print("PASS: iPhone XR/iOS 18 minimum and iOS 26 glass fallback")
print("PASS: idle/screen recording preview budget, buffered memory limits")
print("PASS: full-quality movie pipeline, drop diagnostics and stable style UI")
