import UIKit

/// TextKit 排版：一本章节 → 若干页（NSLayoutManager + 多 NSTextContainer）
final class TextKitPaginator {
    let storage: NSTextStorage
    let layout: NSLayoutManager
    private(set) var containers: [NSTextContainer] = []
    private(set) var ranges: [NSRange] = []

    init(text: String, config: ReaderConfig, size: CGSize, theme: ReaderTheme) {
        let attributed = TextKitPaginator.attributed(text, config: config, theme: theme)
        storage = NSTextStorage(attributedString: attributed)
        layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        guard size.width > 20, size.height > 20, storage.length > 0 else {
            let container = NSTextContainer(size: size)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers = [container]
            ranges = [NSRange(location: 0, length: storage.length)]
            return
        }

        var location = 0
        while location < storage.length {
            let container = NSTextContainer(size: size)
            container.lineFragmentPadding = 0
            container.maximumNumberOfLines = 0
            container.lineBreakMode = .byWordWrapping
            layout.addTextContainer(container)
            containers.append(container)

            let glyphRange = layout.glyphRange(for: container)
            if glyphRange.length == 0 { break }
            let charRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            ranges.append(charRange)
            location = charRange.location + charRange.length
        }
        if ranges.isEmpty {
            ranges = [NSRange(location: 0, length: storage.length)]
        }
    }

    var pageCount: Int { max(1, ranges.count) }

    func container(at index: Int) -> NSTextContainer? {
        guard containers.indices.contains(index) else { return nil }
        return containers[index]
    }

    // MARK: - 属性

    static func attributed(_ text: String, config: ReaderConfig, theme: ReaderTheme) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(config.lineSpacing)
        paragraph.paragraphSpacing = CGFloat(config.paragraphSpacing)
        paragraph.alignment = .justified
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.hyphenationFactor = 0

        let font = uiFont(config)
        let color = UIColor(theme.textHex)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if config.letterSpacing != 0 {
            attributes[.kern] = CGFloat(config.letterSpacing)
        }

        // 每段前面加两个全角空格（原版按字数缩进，这里直接补字符，保证折行后对齐）
        let indent = config.indent ? "\u{3000}\u{3000}" : ""
        let body = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { indent + $0 }
            .joined(separator: "\n")
        return NSAttributedString(string: body, attributes: attributes)
    }

    static func uiFont(_ config: ReaderConfig) -> UIFont {
        let size = CGFloat(config.fontSize)
        let weight: UIFont.Weight
        switch config.fontWeight {
        case 0: weight = .light
        case 2: weight = .bold
        default: weight = .regular
        }
        if !config.fontFamily.isEmpty,
           let custom = UIFont(name: config.fontFamily, size: size) {
            return custom
        }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }
}

private extension UIColor {
    convenience init(_ hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
