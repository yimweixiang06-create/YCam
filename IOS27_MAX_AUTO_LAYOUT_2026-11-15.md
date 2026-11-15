# iOS 27 布局 / 实时手势 / 最高分辨率修正

- 照片不再提供“一半／最大”的双档切换；会话从当前摄像头的 `activeFormat.supportedMaxPhotoDimensions` 获取最大值，`AVCapturePhotoSettings.maxPhotoDimensions` 请求该值，并在 UI 显示实际查询到的 MP。
- 在视频／照片／人像切换或切换镜头后，重新检测当前设备镜头的照片能力，切换前后不会伪装成固定 48MP。实际成片可能比请求的最大值小（Apple AVFoundation 行为）。
- 保留 HEIF/RAW 选择；RAW 最终分辨率受具体 RAW 像素格式限制，不能把 HEIF 的 MP 数当作 RAW 的保证。
- 删除占据取景框的第二条 `1×/2×` 浮动缩放条，缩放改用取景框双指捏合；照片／人像的展开箭头保留，视频不显示。
- 底部的视频／照片／人像条尺寸不随拖动变化，交互结束后只切换一次相机模式。
- 人像六角形光效选择条单独管理拖动局部状态，手指移动时高亮实时跟随，松手后再应用光效，避免每帧重算滤镜。
- 苹果官方：HEIF Max/ProRAW 与 Live Photo 不兼容。当前最大照片超过 24MP 时，Live Photo 不允许暗中降低至半分辨率；设备支持的正常分辨率摄影风格＋Live 仍保留。

验收：`python3 tools/static_check.py`、`python3 tools/style_check.py`、`python3 tools/verify_neutral_controls.py`、`python3 tools/verify_user_layout_max.py`。真机 UI 手势帧率与像素数尚需实机检测。

官方依据：
- https://support.apple.com/guide/iphone/iph263472f78/27/ios/27
- https://support.apple.com/guide/iphone/iph17471d6de/27/ios/27
- https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/supportedmaxphotodimensions
- https://developer.apple.com/videos/play/wwdc2026/304/
