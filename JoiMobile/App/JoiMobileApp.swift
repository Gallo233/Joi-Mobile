import SwiftUI

@main
struct JoiMobileApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootShellView(model: model)
        }
    }
}
