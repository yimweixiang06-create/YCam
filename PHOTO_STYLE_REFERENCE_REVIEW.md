# YCam 摄影风格参考样张与清晰度修订（2026-11-15）

## 风格对比素材（仅作视觉研究，版权归原网站/摄影师，不打包他人照片）

- Apple iPhone 17 官方摄影风格示例：https://www.apple.com/my/iphone-17/ （皮肤亮度、色彩鲜活；官方并未公开配方）
- Apple 官方摄影风格调整指南（iOS 26）：https://support.apple.com/en-gb/guide/iphone/iph629d2cd37/26/ios/26
- Apple 官方摄影风格调整指南（iOS 27）：https://support.apple.com/en-ca/guide/iphone/iph629d2cd37/27/ios/27
- AppleInsider 同一场景 8 种摄影风格示例：https://appleinsider.com/articles/24/10/03/iphone-16-review-bold-colors-new-buttons-promises-for-the-future
- Apple 传统滤镜鲜艳/戏剧/黑白九宫格参考：https://www.apeaksoft.com/edit-photo/add-filters-to-iphone-photos/
- Fujifilm 官方各胶片风格实拍图库：https://www.fujifilm-x.com/global/products/film-simulation/
- FujiFrame 同场景富士胶片风格对照：https://fujiframe.com/film-simulations
- Park Cameras 富士同场景模拟比较：https://www.parkcameras.com/blog/tips-and-inspiration/how-to-get-started-with-fujifilm-film-simulation_tips-28

这些示例不是 YCam 实机对照，也不可能通过照片逆向还原 Apple 的非公开算法；第三方示例不冒充官方标定。图片版权仍属于各自摄影师／网站。

## 功能与默认值

- 所有 CameraStyle 的调色盘：色调 **0**，颜色 **0**，调色盘 **100**。
- 首次进入或切换摄影风格时，圆点居中；CustomPalettePanel 的「重置」也回到 (0,0,100)。
- 风格底色仍由各自的 LookRecipe 决定，所以调色盘在中间不代表把风格变回标准；它代表**不附加用户修改**。
- 珠光、明亮、空灵取消默认的全画面模糊滤色叠加；保留用户自己开启的人像景深虚化和独立控制。
- 按参考样张方向温和调整珠光、冷调玫瑰色、耀目、自然、空灵、明亮的颜色和明暗配方，目标是清楚、自然、有层次，不保证与系统私有算法完全一致。
- 录像/实况/成片仍经同一 FilterEngine 处理。硬件能力与真实帧率仍需 iPhone 测试。

## 检验

```sh
swiftc -frontend -parse *.swift
python tools/static_check.py
python tools/style_check.py
python tools/verify_neutral_controls.py
```
