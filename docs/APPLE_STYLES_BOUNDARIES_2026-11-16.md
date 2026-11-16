# Apple iOS 27 摄影风格行为与 YCam 实现边界 — 2026-11-16

## 已由 Apple 官方说明确认
- Photographic Styles 会智能调整照片**不同区域中的特定颜色**，不是单纯给整张照片叠一种均匀色块。来源：https://support.apple.com/en-gb/guide/iphone/iph629d2cd37/27/ios/27
- 兼容设备拍摄使用「高效」格式时，可以在 Photos 中再次选择与调整风格：Tone、Color、Intensity；设备及功能代际有限制。来源：https://support.apple.com/en-my/guide/iphone/iphb08064d57/27/ios/27
- iPhone 18 Pro / Pro Max 等支持的设备具备更进一步的 Texture、Soft Skin、Glow、Film 及 Grain 操作；并非所有设备均具备。见以上 Apple Support 页面。
- Apple 在 2021 年官方研究《On-device Panoptic Segmentation for Camera Using Transformers》中公开：人物、皮肤、天空分割会辅助 Photographic Styles 的选择性处理、帮助保留肤色；当时研究描述的类别包括天空、人物、头发、皮肤、牙齿和眼镜，并公开了 MobileNetV3+Transformer/HyperDETR 的研究架构。**这说明分割原则是公开的，不代表 2026 年 iOS 27 仍使用同一个模型或同样的每项算法。** 来源：https://machinelearning.apple.com/research/panoptic-segmentation
- Apple 的 iOS 27 用户指南公开了选择、Tone/Color/Intensity 与支持机型的 Texture 控件，但未公开可供第三方复现的完整 ISP 算法、逐风格色彩矩阵、原厂二维底图或 HEIF 内部存储细节。

## 不得当作确定事实的推断
- 「所有 iOS 27 机型、全部风格都在实时管线中使用 skin/sky/plant/building 四类固定掩膜」；2021 年苹果研究确实公开了皮肤/人物/天空等分类及所用研究模型，但不能据此断言建筑/植被掩膜或其最新实现。
- 「所有风格完全作为 HEIF 内的一个独立图层存储」或「重调在数学意义上完全无损」；Apple 公开了支持机型的可编辑行为，但不是完整文件格式。
- 「iOS 摄影风格等同于公开 Core Image 的一组滤镜系数」；
- 「HEIF 里带有自建 YCam 元数据就能在 iOS Photos 的摄影风格面板无损重调」。

## YCam 正确实现路线

核心实施顺序：先建立独立场景与设备回归基准，再使用公开 Vision 的人物/前景分割与可验证的肤色保护策略；天空需要明确的公开模型及许可，不能把简单蓝色阈值称为天空语义分割。对局部 tone mapping 应比较中高光/肤色/暗部削波及边缘伪影；任何对 Swift/LUT 的实质颜色校准，仍需 2000 张有实拍证据样本以及匹配的原图/目标准确度配对与独立 holdout。**目前这些语义与 ISP 级功能尚未在 YCam 中实现。**

1. 优先修正所见即所得、入口原生感：图标与名称、小型横向滑动、独立调色盘的11×11可见点、原一体磨砂面板、同一亮度/纯度二维控制与黄11档强度。
2. 可使用 YCam 自有、经过实际设备测试的局部策略提升肤色/天空保护；不得冒用未公开 Apple ISP 参数。已有 `CIVibrance` 只能做颜色相关的保护倾向，**不等同于真实人体/天空语义识别**。
3. HEIF 支持“可再编辑”需要保留原始图像和 YCam 独立配方记录，并提供 YCam 自己的再次编辑路径；不能保证 iOS Photos 把它识别成 Apple 摄影风格。导出路径必须验证像素、方向、ICC/颜色空间和元数据，不擅自修改用户相册中的文件。
4. 2000 张有许可、有来源、具摄影实拍证据的独特样本是用户对颜色校准的硬门槛。普通照片只能进行质量/肤色/灰阶/高光裁剪回归；只有目标风格每个坐标真正同场景成对基准 + holdout 验证才能优化 LUT/声称目标准确度改善。

本文件是技术路线与边界记录，绝不代表这些尚未实现的功能已经在 App 中可用。
