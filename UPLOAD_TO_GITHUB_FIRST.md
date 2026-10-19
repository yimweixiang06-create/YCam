# 上传到 GitHub 的文件清单（缺一个都可能构建失败）

根目录必须有：

- `.github/workflows/build-unsigned-ipa.yml`
- `YCam.xcodeproj/project.pbxproj`
- `Info.plist`
- `Assets.xcassets/`
- `FilmStyleCameraApp.swift`、`CameraHomeView.swift`、`CameraModel.swift`、`CameraPreview.swift`、
  `DotPalette.swift`、`FilterEngine.swift`、`Styles.swift`、`VideoRecorder.swift`、`Glass.swift`

`tools/`、`docs/`、各种 `.md` 文件不参与编译，可以一起上传，也可以不传。
工作流开头会检查上面这些文件，缺文件会直接给出明确的错误。
