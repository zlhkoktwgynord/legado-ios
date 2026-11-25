import SwiftUI

@main
struct LegadoIOSApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(model.appearance == 1 ? .light : (model.appearance == 2 ? .dark : nil))
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        CloudSyncService.shared.pull(model: model)
                    } else if phase == .background {
                        CloudSyncService.shared.push(model: model)
                    }
                }
        }
    }
}
