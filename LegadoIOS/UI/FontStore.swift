import Foundation
import CoreText

/// 自定义字体：导入 ttf/otf，注册到系统后按 PostScript 名称使用
enum FontStore {

    static var directory: URL {
        let dir = Storage.root.appendingPathComponent("Fonts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 注册 App 内置字体（Roboto 等，Apache-2.0）
    static func registerBundled() {
        let names = ["Roboto-Regular", "DroidSansMono"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func registerAll() {
        registerBundled()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        for url in files where ["ttf", "otf", "ttc"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// 导入字体文件，返回可用的字体名（PostScript 名称）
    static func importFont(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        guard ["ttf", "otf", "ttc"].contains(ext) else { return nil }
        let target = directory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: target)
        guard (try? FileManager.default.copyItem(at: url, to: target)) != nil else { return nil }
        CTFontManagerRegisterFontsForURL(target as CFURL, .process, nil)
        return fontName(for: target)
    }

    /// 已导入的字体（显示名 -> PostScript 名）
    static func importedFonts() -> [(display: String, name: String)] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }
        var result: [(String, String)] = []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard ["ttf", "otf", "ttc"].contains(url.pathExtension.lowercased()) else { continue }
            let name = fontName(for: url) ?? url.deletingPathExtension().lastPathComponent
            let display = url.deletingPathExtension().lastPathComponent
            result.append((display, name))
        }
        return result
    }

    private static func fontName(for url: URL) -> String? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                as? [CTFontDescriptor], let descriptor = descriptors.first else { return nil }
        let postScript = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
        return postScript
    }
}
