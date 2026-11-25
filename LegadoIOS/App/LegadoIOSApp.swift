import SwiftUI

@main
struct LegadoIOSApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(model.appearance == 1 ? .light : (model.appearance == 2 ? .dark : nil))
        }
    }
}
