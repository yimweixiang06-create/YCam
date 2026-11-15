# 人像光效选择盘改版（2026-11-15）

根据 Apple iOS 27 iPhone User Guide，Portrait Lighting 位于取景框底部，使用横向拖动选择光效。此实现尽量贴近原生视觉布局，但不是 Apple 私有控件的逐像素拷贝。

- 移除旧版黑色长胶囊中的六角形选择条。
- 使用紧凑居中的圆形光效图标：选中项为细黄环，顶部以小字号显示光效名称。
- 拖动时 UI 本地实时跟手；松手才提交光效选择，避免反复重算图像。
- 人像光效只在人像模式出现；照片的摄影风格和普通滤镜依然从六点控制菜单进入。
- 不再使用上方白色「未检测到人物」提示胶囊；辅助功能仍能读出检测状态。
- 不恢复已按用户要求移除的第二条 1×／2× 浮动缩放栏。

官方参考：
- https://support.apple.com/en-asia/guide/iphone/iphd7d3a91a2/27/ios/27
- https://support.apple.com/guide/iphone/use-camera-tools-iph3dc593597/27/ios/27

验证：Swift 语法解析、静态检查、28 个摄影风格初值检查和最高分辨率/双指缩放回归检查通过。需要 Xcode 构建及 iPhone 实机验证具体渲染位置与触控手感。
