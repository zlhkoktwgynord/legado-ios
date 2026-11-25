import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// iCloud 同步（NSUbiquitousKeyValueStore）
///
/// 注意：这个能力需要 App 带 iCloud entitlement，并且只能用**付费开发者账号**签名。
/// 免费证书自签的包不要开这个开关，否则装上会报错或同步不可用。
@MainActor
final class CloudSyncService {
    static let shared = CloudSyncService()

    private let store = NSUbiquitousKeyValueStore.default
    private let dataKey = "legado.backup.v1"
    private let remoteStampKey = "legado.remoteStamp"
    private let enabledKey = "cloudSyncEnabled"

    private weak var model: AppModel?
    private var pushTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private var isApplying = false

    /// iCloud 账号是否可用（没有 entitlement 或没登录 iCloud 时返回 nil）
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    func start(model: AppModel) {
        self.model = model
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let model = self.model else { return }
                self.pull(model: model)
            }
        }
        if isEnabled && isAvailable {
            pull(model: model)
        }
    }

    func setEnabled(_ enabled: Bool, model: AppModel) {
        self.model = model
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled {
            pull(model: model)
            push(model: model)
        }
    }

    /// 本地数据变化后延迟推送，避免频繁写
    func schedulePush(model: AppModel) {
        guard isEnabled, isAvailable, !isApplying else { return }
        self.model = model
        pushTask?.cancel()
        pushTask = Task { [weak self, weak model] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self = self, let model = model else { return }
            self.push(model: model)
        }
    }

    func push(model: AppModel) {
        guard isEnabled, isAvailable else { return }
        let payload = BackupService.make(sources: model.sources,
                                         books: model.books,
                                         bookmarks: model.bookmarks,
                                         replaceRules: model.replaceRules,
                                         readerConfig: model.readerConfig)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        guard data.count < 900_000 else {
            model.syncMessage = "数据超过 iCloud 键值存储上限（1MB），请改用备份文件"
            return
        }
        store.set(data, forKey: dataKey)
        store.synchronize()
        UserDefaults.standard.set(payload.exportedAt, forKey: remoteStampKey)
        model.lastSyncAt = Date()
        model.syncMessage = "已上传 \(model.sources.count) 个书源、\(model.books.count) 本书"
    }

    func pull(model: AppModel) {
        guard isEnabled, isAvailable else { return }
        guard let data = store.data(forKey: dataKey),
              let payload = try? JSONDecoder().decode(BackupPayload.self, from: data) else {
            return
        }
        let lastStamp = UserDefaults.standard.double(forKey: remoteStampKey)
        guard Double(payload.exportedAt) > lastStamp else { return }

        isApplying = true
        model.applyRemote(payload)
        UserDefaults.standard.set(payload.exportedAt, forKey: remoteStampKey)
        model.lastSyncAt = Date()
        model.syncMessage = "已从 iCloud 拉取 \(payload.sources.count) 个书源、\(payload.books.count) 本书"
        isApplying = false
    }

    func syncNow(model: AppModel) {
        pull(model: model)
        push(model: model)
    }
}
