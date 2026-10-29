# YCam（iOS 26 相机风格）

- 界面按你的 iOS 26 截图和录屏重做：视频｜照片｜人像、4:3 取景器 + 展开按钮、⋯ 控制抽屉（可编辑）、摄影风格 / 滤镜 / 自定义色调板、变焦、景深、人像光效。
- iOS 26 的控件用官方 Liquid Glass；iOS 18 自动换成磨砂玻璃；底部面板是高斯磨砂。
- 构建：把整个文件夹（包括隐藏的 `.github`）上传 GitHub → Actions → **Build YCam for Sideloadly** → 下载 `YCam-unsigned-IPA` → Sideloadly 签名安装。需要 Xcode 26 SDK，工作流会强制并检查。
- **先看 `CHANGES.md`**：做了什么、哪些没验证（没编译、没真机、没测 90% 还原度）。
- 手机上出问题时：长按右上角胶囊里的“⋯”约 1 秒打开**诊断日志**，点“复制全部”发给我。
- 自检：`python3 tools/static_check.py`、`python3 tools/style_check.py`。
