import SwiftUI

@main
struct LegadoIOSApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var chrome = HomeChrome()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(chrome)
                .preferredColorScheme(model.appearance == 1 ? .light : (model.appearance == 2 ? .dark : nil))
        }
    }
}
