# 没有 Mac 怎么得到 IPA

1. 在 GitHub 新建一个仓库（私有即可）。
2. 把本压缩包解压后的**全部内容**上传到仓库根目录。注意要包含隐藏文件夹 `.github`（里面是工作流）。网页上传看不到隐藏文件夹时，用 GitHub Desktop 或 `git` 命令行上传。
3. 打开仓库的 **Actions** → 选 **Build YCam for Sideloadly** → **Run workflow**。
4. 成功后在运行页面底部 **Artifacts** 下载 `YCam-unsigned-IPA`，解压得到 `YCam-unsigned.ipa`。
5. 用 Sideloadly 选择这个 IPA，用你的 Apple ID 签名安装。
6. 如果构建失败：下载同页面的 `YCam-build-logs`（里面有 `xcodebuild.log`），把报错贴给我。
   - 工作流的第一个检查是 Xcode 版本必须 ≥ 26；失败信息会写明原因。
   - 构建成功后会打印 “Liquid Glass symbol references in the binary”，数字大于 0 说明官方玻璃 API 确实被编进了 App。
