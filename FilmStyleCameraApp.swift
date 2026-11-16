import SwiftUI

@main
struct YCamApp: App {
    var body: some Scene {
        WindowGroup {
            CameraHomeView()
                .preferredColorScheme(.dark)
        }
    }
}

// Uses the selected language for YCam only (iOS Settings > Apps > YCam).
// Never override AppleLanguages; the device language remains untouched.
extension String {
    var ycamLocalized: String {
        NSLocalizedString(self, comment: "YCam camera UI")
    }
}
