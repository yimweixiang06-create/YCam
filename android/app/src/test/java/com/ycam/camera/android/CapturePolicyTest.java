package com.ycam.camera.android;

import static org.junit.Assert.assertEquals;
import org.junit.Test;

public final class CapturePolicyTest {
    @Test public void zoomClampsAtCameraLimits() {
        assertEquals(1f, CapturePolicy.clampZoom(0.2f, 1f, 10f), 0.0001f);
        assertEquals(3f, CapturePolicy.clampZoom(3f, 1f, 10f), 0.0001f);
        assertEquals(10f, CapturePolicy.clampZoom(24f, 1f, 10f), 0.0001f);
    }
    @Test public void rejectsNanAndInfinity() {
        assertEquals(0.5f, CapturePolicy.clampZoom(Float.NaN, 0.5f, 5f), 0.0001f);
        assertEquals(0.5f, CapturePolicy.clampZoom(Float.POSITIVE_INFINITY, 0.5f, 5f), 0.0001f);
    }
}
