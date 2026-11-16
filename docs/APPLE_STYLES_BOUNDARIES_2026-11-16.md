# Apple iOS 27 摄影风格行为与 YCam 实现边界 — 2026-11-16

## 已由 Apple 官方说明确认
- Photographic Styles 会智能调整照片**不同区域中的特定颜色**，不是单纯给整张照片叠一种均匀色块。来源：https://support.apple.com/en-gb/guide/iphone/iph629d2cd37/27/ios/27
- 兼容设备拍摄使用「高效」格式时，可以在 Photos 中再次选择与调整风格：Tone、Color、Intensity；设备及功能代际有限制。来源：https://support.apple.com/en-my/guide/iphone/iphb08064d57/27/ios/27
- iPhone 18 Pro / Pro Max 等支持的设备具备更进一步的 Texture、Soft Skin、Glow、Film 及 Grain 操作；并非所有设备均具备。见以上 Apple Support 页面。
- Apple 只公开功能层面的描述；并没有在此公开用于复现原厂风格的具体语义分割类别与模型、ISP 数学模型、完整二维底图或 3D 色彩矩阵。

## 不得当作确定事实的推断
- 「Apple 一定把 skin/sky/plant/building 分成四个独立掩膜」或其训练模型/矩阵；
- 「所有风格完全作为 HEIF 内的一个独立图层存储」；
- 「iOS 摄影风格等同于公开 Core Image 的一组滤镜系数」；
- 「HEIF 里带有自建 YCam 元数据就能在 iOS Photos 的摄影风格面板无损重调」。

## YCam 正确实现路线
1. 优先修正所见即所得、入口原生感：图标与名称、小型横向滑动、独立调色盘的11×11可见点、原一体磨砂面板、同一亮度/纯度二维控制与黄11档强度。
2. 可使用 YCam 自有、经过实际设备测试的局部策略提升肤色/天空保护；不得冒用未公开 Apple ISP 参数。已有 `CIVibrance` 只能做颜色相关的保护倾向，**不等同于真实人体/天空语义识别**。
3. HEIF 支持“可再编辑”需要保留原始图像和 YCam 独立配方记录，并提供 YCam 自己的再次编辑路径；不能保证 iOS Photos 把它识别成 Apple 摄影风格。导出路径必须验证像素、方向、ICC/颜色空间和元数据，不擅自修改用户相册中的文件。
4. 2000 张有许可、有来源、具摄影实拍证据的独特样本是用户对颜色校准的硬门槛。普通照片只能进行质量/肤色/灰阶/高光裁剪回归；只有目标风格每个坐标真正同场景成对基准 + holdout 验证才能优化 LUT/声称目标准确度改善。

本文件是技术路线与边界记录，绝不代表这些尚未实现的功能已经在 App 中可用。
