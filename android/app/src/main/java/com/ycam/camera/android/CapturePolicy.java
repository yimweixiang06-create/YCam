package com.ycam.camera.android;

final class CapturePolicy {
    private CapturePolicy() {}

    static float clampZoom(float value, float min, float max) {
        if (Float.isNaN(value) || Float.isInfinite(value)) return min;
        return Math.max(min, Math.min(max, value));
    }
}
