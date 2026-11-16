package com.ycam.camera.android;

import android.Manifest;
import android.content.ActivityNotFoundException;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.GestureDetector;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.FocusMeteringAction;
import androidx.camera.core.ImageCapture;
import androidx.camera.core.ImageCaptureException;
import androidx.camera.core.MeteringPoint;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.video.MediaStoreOutputOptions;
import androidx.camera.video.Quality;
import androidx.camera.video.QualitySelector;
import androidx.camera.video.Recorder;
import androidx.camera.video.Recording;
import androidx.camera.video.VideoCapture;
import androidx.camera.video.VideoRecordEvent;
import androidx.camera.view.PreviewView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import com.google.common.util.concurrent.ListenableFuture;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.TimeUnit;

/**
 * Native Android camera foundation. This is not a port of Apple's AVFoundation,
 * Photographic Styles, Live Photo or YCam's iPhone LUT processing.
 * Supported today: preview, AF/AE touch, pinch zoom, photo, video, mic (optional),
 * front/back selection, flash/torch, Gallery save and open.
 */
public final class MainActivity extends AppCompatActivity {
    private static final int REQ_CAMERA = 100;
    private static final int REQ_MIC = 101;

    private PreviewView previewView;
    private TextView status;
    private Button photoModeButton, videoModeButton, shutterButton, flashButton, switchButton;
    private ProcessCameraProvider cameraProvider;
    private Camera camera;
    private ImageCapture imageCapture;
    private VideoCapture<Recorder> videoCapture;
    private Recording recording;
    private boolean isVideo = false;
    private boolean busy = false;
    private boolean torch = false;
    private boolean flash = false;
    private int lensFacing = CameraSelector.LENS_FACING_BACK;
    private Uri lastCaptureUri;
    private String lastCaptureMime;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(Color.BLACK);
        getWindow().setNavigationBarColor(Color.BLACK);
        buildUi();
        if (hasCameraPermission()) {
            startCamera();
        } else {
            setStatus(getString(R.string.camera_permission));
            ActivityCompat.requestPermissions(this,
                    new String[]{Manifest.permission.CAMERA}, REQ_CAMERA);
        }
    }

    private boolean hasCameraPermission() {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED;
    }

    private boolean hasAudioPermission() {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED;
    }

    private int dp(int size) {
        return Math.round(getResources().getDisplayMetrics().density * size);
    }

    private GradientDrawable rounded(int color, int radius) {
        GradientDrawable result = new GradientDrawable();
        result.setColor(color);
        result.setCornerRadius(dp(radius));
        return result;
    }

    private Button button(int textRes, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(textRes);
        button.setAllCaps(false);
        button.setTextColor(Color.WHITE);
        button.setTextSize(13);
        button.setBackground(rounded(0xD92C2C30, 18));
        button.setOnClickListener(listener);
        return button;
    }

    private void buildUi() {
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        previewView = new PreviewView(this);
        previewView.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        root.addView(previewView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        ScaleGestureDetector zoomDetector = new ScaleGestureDetector(this,
                new ScaleGestureDetector.SimpleOnScaleGestureListener() {
                    @Override public boolean onScale(@NonNull ScaleGestureDetector detector) {
                        if (camera == null || camera.getCameraInfo().getZoomState().getValue() == null) {
                            return false;
                        }
                        androidx.camera.core.ZoomState zoom =
                                camera.getCameraInfo().getZoomState().getValue();
                        float next = CapturePolicy.clampZoom(
                                zoom.getZoomRatio() * detector.getScaleFactor(),
                                zoom.getMinZoomRatio(), zoom.getMaxZoomRatio());
                        camera.getCameraControl().setZoomRatio(next);
                        return true;
                    }
                });

        GestureDetector focusDetector = new GestureDetector(this,
                new GestureDetector.SimpleOnGestureListener() {
                    @Override public boolean onSingleTapUp(@NonNull MotionEvent event) {
                        if (camera == null) return false;
                        MeteringPoint point = previewView.getMeteringPointFactory()
                                .createPoint(event.getX(), event.getY());
                        FocusMeteringAction action = new FocusMeteringAction.Builder(point)
                                .setAutoCancelDuration(3, TimeUnit.SECONDS)
                                .build();
                        camera.getCameraControl().startFocusAndMetering(action);
                        return true;
                    }
                });
        previewView.setOnTouchListener((v, event) -> {
            zoomDetector.onTouchEvent(event);
            if (!zoomDetector.isInProgress()) focusDetector.onTouchEvent(event);
            return true;
        });

        status = new TextView(this);
        status.setTextColor(Color.WHITE);
        status.setTextSize(13);
        status.setPadding(dp(14), dp(10), dp(14), dp(10));
        status.setBackground(rounded(0xCC111117, 14));
        status.setText(R.string.camera_starting);
        status.setOnClickListener(v -> openLastCapture());
        FrameLayout.LayoutParams statusParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP);
        statusParams.setMargins(dp(14), dp(32), dp(14), 0);
        root.addView(status, statusParams);

        LinearLayout controls = new LinearLayout(this);
        controls.setOrientation(LinearLayout.VERTICAL);
        controls.setPadding(dp(12), dp(12), dp(12), dp(18));
        controls.setBackground(rounded(0xE6101016, 22));

        TextView notice = new TextView(this);
        notice.setText(R.string.preview_notice);
        notice.setTextColor(0xFFCACACA);
        notice.setTextSize(11);
        notice.setGravity(Gravity.CENTER);
        controls.addView(notice, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        LinearLayout modes = new LinearLayout(this);
        modes.setGravity(Gravity.CENTER);
        photoModeButton = button(R.string.photo, v -> switchMode(false));
        videoModeButton = button(R.string.video, v -> switchMode(true));
        LinearLayout.LayoutParams modeParams = new LinearLayout.LayoutParams(0, dp(44), 1);
        modeParams.setMargins(dp(3), dp(10), dp(3), dp(10));
        modes.addView(photoModeButton, modeParams);
        LinearLayout.LayoutParams nextModeParams = new LinearLayout.LayoutParams(0, dp(44), 1);
        nextModeParams.setMargins(dp(3), dp(10), dp(3), dp(10));
        modes.addView(videoModeButton, nextModeParams);
        controls.addView(modes);

        LinearLayout actions = new LinearLayout(this);
        actions.setGravity(Gravity.CENTER_VERTICAL);
        flashButton = button(R.string.flash_off, v -> toggleLight());
        switchButton = button(R.string.switch_camera, v -> switchLens());
        shutterButton = button(R.string.take_photo, v -> {
            if (isVideo) toggleVideoRecording();
            else capturePhoto();
        });
        shutterButton.setTextSize(15);
        shutterButton.setBackground(rounded(0xFFB18B13, 38));
        LinearLayout.LayoutParams small = new LinearLayout.LayoutParams(0, dp(58), 1);
        small.setMargins(dp(2), 0, dp(2), 0);
        actions.addView(flashButton, small);
        LinearLayout.LayoutParams big = new LinearLayout.LayoutParams(0, dp(72), 1.25f);
        big.setMargins(dp(5), 0, dp(5), 0);
        actions.addView(shutterButton, big);
        LinearLayout.LayoutParams flip = new LinearLayout.LayoutParams(0, dp(58), 1);
        flip.setMargins(dp(2), 0, dp(2), 0);
        actions.addView(switchButton, flip);
        controls.addView(actions);

        FrameLayout.LayoutParams controlParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM);
        controlParams.setMargins(dp(12), 0, dp(12), dp(28));
        root.addView(controls, controlParams);
        setContentView(root);
        updateButtons();
    }

    private void setStatus(String text) {
        runOnUiThread(() -> status.setText(text));
    }

    private void startCamera() {
        if (!hasCameraPermission()) return;
        ListenableFuture<ProcessCameraProvider> future = ProcessCameraProvider.getInstance(this);
        future.addListener(() -> {
            try {
                cameraProvider = future.get();
                bindCamera();
            } catch (Exception error) {
                setStatus(getString(R.string.camera_unavailable) + " " + error.getMessage());
            }
        }, ContextCompat.getMainExecutor(this));
    }

    private void bindCamera() {
        if (cameraProvider == null || recording != null || !hasCameraPermission()) return;
        cameraProvider.unbindAll();
        camera = null;
        CameraSelector selector = new CameraSelector.Builder()
                .requireLensFacing(lensFacing).build();
        try {
            if (!cameraProvider.hasCamera(selector)) {
                lensFacing = CameraSelector.LENS_FACING_BACK;
                selector = CameraSelector.DEFAULT_BACK_CAMERA;
            }
            Preview preview = new Preview.Builder().build();
            preview.setSurfaceProvider(previewView.getSurfaceProvider());
            imageCapture = new ImageCapture.Builder()
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                    .setFlashMode(flash ? ImageCapture.FLASH_MODE_ON : ImageCapture.FLASH_MODE_OFF)
                    .build();
            Recorder recorder = new Recorder.Builder()
                    .setQualitySelector(QualitySelector.from(Quality.HIGHEST)).build();
            videoCapture = VideoCapture.withOutput(recorder);

            // Try concurrent preview+photo+video for a quick mode switch.
            // Fall back to preview + selected use case on devices whose
            // camera pipeline cannot support all three at once.
            try {
                camera = cameraProvider.bindToLifecycle(this, selector,
                        preview, imageCapture, videoCapture);
            } catch (IllegalArgumentException | IllegalStateException unsupported) {
                cameraProvider.unbindAll();
                camera = isVideo
                        ? cameraProvider.bindToLifecycle(this, selector, preview, videoCapture)
                        : cameraProvider.bindToLifecycle(this, selector, preview, imageCapture);
            }
            torch = false;
            updateButtons();
            setStatus(isVideo ? getString(R.string.video) : getString(R.string.photo));
        } catch (Exception error) {
            camera = null;
            updateButtons();
            setStatus(getString(R.string.mode_unavailable) + " " + error.getMessage());
        }
    }

    private void updateButtons() {
        boolean available = camera != null;
        photoModeButton.setBackground(rounded(isVideo ? 0xD92C2C30 : 0xFF7B6330, 18));
        videoModeButton.setBackground(rounded(isVideo ? 0xFF7B6330 : 0xD92C2C30, 18));
        shutterButton.setText(isVideo
                ? (recording == null ? R.string.start_video : R.string.stop_video)
                : R.string.take_photo);
        shutterButton.setEnabled(available && (!busy || recording != null));
        photoModeButton.setEnabled(!busy);
        videoModeButton.setEnabled(!busy);
        switchButton.setEnabled(!busy && available);
        flashButton.setEnabled(available && camera.getCameraInfo().hasFlashUnit());
        flashButton.setText(isVideo
                ? (torch ? R.string.torch_on : R.string.torch_off)
                : (flash ? R.string.flash_on : R.string.flash_off));
    }

    private void switchMode(boolean video) {
        if (busy || recording != null || isVideo == video) return;
        isVideo = video;
        if (cameraProvider != null) bindCamera();
        updateButtons();
    }

    private void switchLens() {
        if (busy || recording != null) return;
        lensFacing = lensFacing == CameraSelector.LENS_FACING_BACK
                ? CameraSelector.LENS_FACING_FRONT : CameraSelector.LENS_FACING_BACK;
        flash = false;
        torch = false;
        bindCamera();
    }

    private void toggleLight() {
        if (camera == null || !camera.getCameraInfo().hasFlashUnit()) return;
        if (isVideo) {
            torch = !torch;
            camera.getCameraControl().enableTorch(torch);
        } else {
            flash = !flash;
            if (imageCapture != null) {
                imageCapture.setFlashMode(flash ? ImageCapture.FLASH_MODE_ON
                        : ImageCapture.FLASH_MODE_OFF);
            }
        }
        updateButtons();
    }

    private String newFilename(String extension) {
        String stamp = new SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US)
                .format(new Date());
        return "YCam_" + stamp + extension;
    }

    private void capturePhoto() {
        if (busy || camera == null || imageCapture == null) return;
        busy = true;
        updateButtons();
        setStatus(getString(R.string.saving));
        ContentValues values = new ContentValues();
        values.put(MediaStore.Images.Media.DISPLAY_NAME, newFilename(".jpg"));
        values.put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg");
        values.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/YCam");
        ImageCapture.OutputFileOptions options =
                new ImageCapture.OutputFileOptions.Builder(getContentResolver(),
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values).build();
        imageCapture.takePicture(options, ContextCompat.getMainExecutor(this),
                new ImageCapture.OnImageSavedCallback() {
                    @Override public void onImageSaved(
                            @NonNull ImageCapture.OutputFileResults result) {
                        busy = false;
                        lastCaptureUri = result.getSavedUri();
                        lastCaptureMime = "image/jpeg";
                        setStatus(getString(R.string.photo_saved));
                        updateButtons();
                    }
                    @Override public void onError(@NonNull ImageCaptureException error) {
                        busy = false;
                        setStatus(getString(R.string.capture_failed) + " " + error.getMessage());
                        updateButtons();
                    }
                });
    }

    private void toggleVideoRecording() {
        if (recording != null) {
            recording.stop();
            busy = true; // Wait for VideoRecordEvent.Finalize before rebinding.
            updateButtons();
            return;
        }
        if (busy || camera == null || videoCapture == null) return;
        if (!hasAudioPermission()) {
            Toast.makeText(this, R.string.audio_permission, Toast.LENGTH_LONG).show();
            // Audio is optional; don't block silent video capture.
            ActivityCompat.requestPermissions(this,
                    new String[]{Manifest.permission.RECORD_AUDIO}, REQ_MIC);
            return;
        }
        beginVideoRecording();
    }

    private void beginVideoRecording() {
        if (busy || recording != null || videoCapture == null) return;
        ContentValues values = new ContentValues();
        values.put(MediaStore.Video.Media.DISPLAY_NAME, newFilename(".mp4"));
        values.put(MediaStore.Video.Media.MIME_TYPE, "video/mp4");
        values.put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/YCam");
        MediaStoreOutputOptions options = new MediaStoreOutputOptions.Builder(
                getContentResolver(), MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
                .setContentValues(values).build();
        try {
            androidx.camera.video.PendingRecording pending =
                    videoCapture.getOutput().prepareRecording(this, options);
            if (hasAudioPermission()) pending = pending.withAudioEnabled();
            busy = true;
            recording = pending.start(ContextCompat.getMainExecutor(this), event -> {
                if (event instanceof VideoRecordEvent.Start) {
                    setStatus(getString(R.string.recording));
                } else if (event instanceof VideoRecordEvent.Finalize) {
                    VideoRecordEvent.Finalize completed = (VideoRecordEvent.Finalize) event;
                    if (!completed.hasError()) {
                        lastCaptureUri = completed.getOutputResults().getOutputUri();
                        lastCaptureMime = "video/mp4";
                        setStatus(getString(R.string.video_saved));
                    } else {
                        setStatus(getString(R.string.capture_failed) + " " + completed.getError());
                    }
                    recording = null;
                    busy = false;
                    updateButtons();
                }
            });
            updateButtons();
        } catch (SecurityException | IllegalStateException error) {
            busy = false;
            recording = null;
            setStatus(getString(R.string.capture_failed) + " " + error.getMessage());
            updateButtons();
        }
    }

    private void openLastCapture() {
        if (lastCaptureUri == null) return;
        Intent intent = new Intent(Intent.ACTION_VIEW)
                .setDataAndType(lastCaptureUri, lastCaptureMime)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            startActivity(intent);
        } catch (ActivityNotFoundException error) {
            Toast.makeText(this, R.string.open_gallery, Toast.LENGTH_SHORT).show();
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode,
            @NonNull String[] permissions, @NonNull int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode == REQ_CAMERA) {
            if (hasCameraPermission()) startCamera();
            else setStatus(getString(R.string.camera_permission));
        } else if (requestCode == REQ_MIC && isVideo && camera != null) {
            // Silent fallback if permission was denied.
            beginVideoRecording();
        }
    }

    @Override
    protected void onStop() {
        if (recording != null) recording.stop();
        super.onStop();
    }

    @Override
    protected void onDestroy() {
        if (recording != null) {
            recording.close();
            recording = null;
        }
        if (cameraProvider != null) cameraProvider.unbindAll();
        super.onDestroy();
    }
}
