# Apple 摄影风格与 YCam 参数说明（2026-11-15）

## 官方资料

- 苹果《通过 iPhone 相机使用摄影风格》：https://support.apple.com/zh-cn/guide/iphone/iph629d2cd37/27/ios/27
- 苹果《在 iPhone 上编辑照片和视频》：https://support.apple.com/zh-cn/guide/iphone/iphb08064d57/27/ios/27
- 苹果 iPhone 17 新闻： https://www.apple.com/my/newsroom/2025/09/apple-introduces-iphone-17/
- Apple Developer 《Capturing still and Live Photos》： https://developer.apple.com/documentation/avfoundation/capturing-still-and-live-photos

苹果官方确认：新一代摄影风格允许拖动二维色调/颜色调色盘，下方的滑块调整应用强度；iPhone 17 新增 Bright（耀目）风格。Apple 没有公开各风格的底层算法、LUT 或完整数值预设。YCam 不调用私有摄影风格 API，使用可移植的 Core Image 颜色处理链模拟视觉效果，无法声称与 Apple 处理完全一致。

## 用户截图可直接读出的数值（**不代表 Apple 发布的默认参数**）

| 参考风格 | 色调 | 颜色 | 调色盘强度 |
|---|---:|---:|---:|
| 标准 | 00 | 00 | 未显示（YCam 用 100） |
| 珠光 | 45 | 90 | 100 |
| 冷调玫瑰色 | 35 | -20 | 75 |

这些是截图中的**用户设置值**，不一定是风格出厂默认值；仅作为用户图片中的调节例子，**YCam 不用这些数值作为任何风格的初始值**。所有风格一律从 00/00/100 开始，让用户自行调节。

## 修改方式

- 横向颜色为 −100…+100，纵向色调为 +100…−100，强度 0…100；复位恢复所有风格共同的中性控制点 0/0/100。
- 切换风格时自动重置为中性控制点；不再把左端强制变灰，支持负色彩数值。
- 色调/颜色从用户拖动的**中性圆点**计算增量，不自动加载截图中的调节读数。
- YCam 的颜色调节方向、强度系数为项目实现，不是 Apple 标定数值。不同设备的 HDR、白平衡、肤色检测会造成实机差异。
- 保留原来的富士 9 套数据集，预览/照片/视频/实况仍走同一份色彩管线；未修改权限、签名或私钥。
