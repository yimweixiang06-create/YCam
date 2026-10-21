import SwiftUI
import UIKit

/// 运行诊断日志：没有 Mac 也能看到 App 里到底发生了什么。
/// 在相机界面长按右上角胶囊里的“⋯”（六个点）约 1 秒即可打开，点“复制全部”后把内容发给我。
final class DiagnosticsLog: ObservableObject, @unchecked Sendable {
    static let shared = DiagnosticsLog()

    @Published private(set) var lines: [String] = []

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// 可以在任意线程调用。
    func add(_ text: String) {
        let line = "\(Self.formatter.string(from: Date()))  \(text)"
        DispatchQueue.main.async {
            self.lines.append(line)
            if self.lines.count > 300 { self.lines.removeFirst(self.lines.count - 300) }
        }
    }

    func clear() {
        DispatchQueue.main.async { self.lines.removeAll() }
    }
}

struct DiagnosticsView: View {
    @ObservedObject private var log = DiagnosticsLog.shared
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var report: String {
        let header = "YCam 诊断 | \(UIDevice.current.model) | iOS \(UIDevice.current.systemVersion)"
        return ([header] + log.lines).joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Text("诊断日志").font(.headline)
                Spacer()
                Button(copied ? "已复制" : "复制全部") {
                    UIPasteboard.general.string = report
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                Button("清除") { log.clear() }
                Button("关闭") { dismiss() }
            }
            .buttonStyle(.borderless)
            .tint(Color.yellow)

            ScrollView {
                Text(report)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .foregroundStyle(Color.white)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
