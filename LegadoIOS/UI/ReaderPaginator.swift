import SwiftUI
import UIKit
import CoreText

/// 把一个章节的正文按给定尺寸切成若干页（CoreText 排版，保证测量和绘制一致）
enum ReaderPaginator {

    static func attributedString(_ text: String, config: ReaderConfig) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(config.lineSpacing)
        paragraph.paragraphSpacing = CGFloat(config.paragraphSpacing)
        paragraph.alignment = .justified
        if config.indent {
            paragraph.firstLineHeadIndent = CGFloat(config.fontSize) * 2
        }
        paragraph.headIndent = 0
        paragraph.tailIndent = 0

        let weight: UIFont.Weight
        switch config.fontWeight {
        case 0: weight = .light
        case 2: weight = .bold
        default: weight = .regular
        }
        let font: UIFont
        if !config.fontFamily.isEmpty,
           let custom = UIFont(name: config.fontFamily, size: CGFloat(config.fontSize)) {
            font = custom
        } else {
            font = UIFont.systemFont(ofSize: CGFloat(config.fontSize), weight: weight)
        }

        let color = UIColor(Color(hex: config.theme.textHex))
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if config.letterSpacing != 0 {
            attributes[.kern] = CGFloat(config.letterSpacing)
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    static func pages(_ text: String, config: ReaderConfig, size: CGSize) -> [NSRange] {
        guard size.width > 40, size.height > 40, !text.isEmpty else {
            return [NSRange(location: 0, length: (text as NSString).length)]
        }
        let attributed = attributedString(text, config: config)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        var result: [NSRange] = []
        var location = 0
        let total = attributed.length
        while location < total {
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path,
                nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length <= 0 { break }
            result.append(NSRange(location: visible.location, length: visible.length))
            location = visible.location + visible.length
        }
        return result.isEmpty ? [NSRange(location: 0, length: total)] : result
    }
}

/// 单页文字绘制视图
struct PageTextView: UIViewRepresentable {
    let attributed: NSAttributedString
    let range: NSRange

    func makeUIView(context: Context) -> PageDrawView {
        let view = PageDrawView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.contentMode = .redraw
        return view
    }

    func updateUIView(_ view: PageDrawView, context: Context) {
        view.attributed = attributed
        view.range = range
        view.setNeedsDisplay()
    }
}

final class PageDrawView: UIView {
    var attributed: NSAttributedString?
    var range: NSRange = NSRange(location: 0, length: 0)

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let attributed = attributed,
              range.length > 0,
              range.location + range.length <= attributed.length else { return }

        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        let path = CGPath(rect: CGRect(origin: .zero, size: bounds.size), transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: range.location, length: range.length),
            path,
            nil)
        CTFrameDraw(frame, context)
    }
}


/// TextKit 单页绘制视图
struct TextKitPageView: UIViewRepresentable {
    let paginator: TextKitPaginator
    let index: Int

    func makeUIView(context: Context) -> TextKitDrawView {
        let view = TextKitDrawView()
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ view: TextKitDrawView, context: Context) {
        view.paginator = paginator
        view.index = index
        view.setNeedsDisplay()
    }
}

final class TextKitDrawView: UIView {
    var paginator: TextKitPaginator?
    var index: Int = 0

    override func draw(_ rect: CGRect) {
        guard let paginator = paginator,
              let container = paginator.container(at: index) else { return }
        let layout = paginator.layout
        let glyphRange = layout.glyphRange(for: container)
        guard glyphRange.length > 0 else { return }
        layout.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
    }
}
