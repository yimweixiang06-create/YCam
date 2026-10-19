# YCam（iOS 26 相机风格）

- 界面按你的 iOS 26 截图和录屏重做：右上角玻璃胶囊、4:3 取景器 + 展开按钮、快门、视频｜照片滑动透镜、⋯ 控制抽屉、风格卡片轮播、自定义圆点板。
- iOS 26 使用官方 Liquid Glass；iOS 18–25 自动使用磨砂玻璃（同一份界面和手势，只换玻璃）。
- 取景器、照片、视频都应用同一套风格（17 个风格，含珠光与 4 个胶片风格）。
- 构建：把整个文件夹（包括隐藏的 `.github`）上传 GitHub → Actions → **Build YCam for Sideloadly** → 下载 `YCam-unsigned-IPA` → Sideloadly 签名安装。需要 Xcode 26 SDK，工作流会强制并检查。
- **先看 `AUDIT_REPORT.md`**：哪些检查过、哪些没有（没编译、没真机、没测 90% 还原度）。
- 自检：`python3 tools/static_check.py`、`python3 tools/style_check.py`。
