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
