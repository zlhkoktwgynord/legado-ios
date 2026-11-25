import Foundation

#if canImport(JavaScriptCore)
import JavaScriptCore

/// 书源 JS 规则执行环境（JavaScriptCore 版）
/// 提供了 Legado 里最常用的一批 java.* / 全局变量绑定
final class JSEngine {
    static let shared = JSEngine()

    private let lock = NSLock()

    struct Context {
        var rule: AnalyzeRule
        var bindings: [String: Any]
    }

    /// 同步求值一次 JS，返回 String / Double / [Any] / [String: Any] 或 nil
    func evaluate(_ js: String, context: Context) -> Any? {
        lock.lock()
        defer { lock.unlock() }

        guard let jsContext = JSContext() else { return nil }
        var exceptionMessage: String?
        jsContext.exceptionHandler = { _, exception in
            exceptionMessage = exception?.toString() ?? "unknown"
        }

        let bridge = JSBridge()
        bridge.rule = context.rule
        jsContext.setObject(bridge, forKeyedSubscript: "java" as NSString)
        jsContext.setObject(context.rule.sourceKey, forKeyedSubscript: "sourceKey" as NSString)

        for (key, value) in context.bindings {
            if let obj = value as? NSObject {
                jsContext.setObject(obj, forKeyedSubscript: key as NSString)
            }
        }
        jsContext.setObject(context.rule.jsBookObject, forKeyedSubscript: "book" as NSString)
        jsContext.setObject(context.rule.jsSourceObject, forKeyedSubscript: "source" as NSString)
        jsContext.setObject(context.rule.chapterObject, forKeyedSubscript: "chapter" as NSString)
        jsContext.setObject(context.rule.baseUrl, forKeyedSubscript: "baseUrl" as NSString)
        jsContext.setObject(context.rule.resultObject, forKeyedSubscript: "result" as NSString)
        jsContext.setObject(context.rule.allVariables, forKeyedSubscript: "variables" as NSString)

        let value = jsContext.evaluateScript(js)
        if let msg = exceptionMessage {
            Log.warn("JS 执行出错: \(msg)")
            return nil
        }
        return Self.convert(value)
    }

    static func convert(_ value: JSValue?) -> Any? {
        guard let value = value else { return nil }
        if value.isUndefined || value.isNull { return nil }
        if value.isString { return value.toString() }
        if value.isBoolean { return value.toBool() }
        if value.isNumber { return value.toDouble() }
        if value.isArray {
            if let arr = value.toObject() as? [Any] { return arr }
            return value.toArray()
        }
        if value.isObject {
            if let dict = value.toObject() as? [String: Any] { return dict }
            return value.toString()
        }
        return value.toString()
    }
}

// MARK: - java.* 桥接

@objc protocol JSBridgeExport: JSExport {
    func ajax(_ url: Any?) -> String
    func connect(_ url: Any?) -> String
    func get(_ key: String) -> String
    func put(_ key: String, _ value: String) -> String
    func log(_ message: Any?)
    func toast(_ message: Any?)
    func base64Encode(_ text: String) -> String
    func base64Decode(_ text: String) -> String
    func md5Encode(_ text: String) -> String
    func md5Encode16(_ text: String) -> String
    func timeFormat(_ time: Any?) -> String
    func htmlFormat(_ html: String) -> String
}

final class JSBridge: NSObject, JSBridgeExport {
    weak var rule: AnalyzeRule?

    func ajax(_ url: Any?) -> String {
        guard let urlStr = Self.stringValue(url) else { return "" }
        return rule?.fetchSync(urlStr) ?? ""
    }

    func connect(_ url: Any?) -> String {
        guard let urlStr = Self.stringValue(url) else { return "" }
        guard let data = rule?.fetchSyncData(urlStr) else { return "" }
        return data.base64EncodedString()
    }

    func get(_ key: String) -> String { rule?.variable(key) ?? "" }

    func put(_ key: String, _ value: String) -> String {
        rule?.setVariable(key, value)
        return value
    }

    func log(_ message: Any?) {
        Log.info("[JS] \(message.map { "\($0)" } ?? "nil")")
    }

    func toast(_ message: Any?) {
        Log.info("[JS toast] \(message.map { "\($0)" } ?? "nil")")
    }

    func base64Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    func base64Decode(_ text: String) -> String {
        guard let data = Data(base64Encoded: text) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func md5Encode(_ text: String) -> String {
        MD5.hash(text)
    }

    func md5Encode16(_ text: String) -> String {
        String(MD5.hash(text).dropFirst(8).dropLast(8))
    }

    func timeFormat(_ time: Any?) -> String {
        var timestamp: Double = 0
        if let d = time as? Double { timestamp = d }
        else if let n = time as? NSNumber { timestamp = n.doubleValue }
        else if let s = time as? String, let d = Double(s) { timestamp = d }
        if timestamp > 10_000_000_000 { timestamp /= 1000 }
        let date = Date(timeIntervalSince1970: timestamp)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd HH:mm"
        return fmt.string(from: date)
    }

    func htmlFormat(_ html: String) -> String {
        TextCleaner.htmlToPlain(html)
    }

    static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let a as [Any]: return a.first.map { "\($0)" }
        case .none: return nil
        case .some(let v): return "\(v)"
        }
    }
}

#else

/// 非 Apple 平台（如 Linux 命令行校验）没有 JavaScriptCore，
/// 用占位实现保证代码可以编译，运行时会返回 nil
final class JSEngine {
    struct Context {
        var rule: AnalyzeRule
        var bindings: [String: Any]
    }

    static let shared = JSEngine()

    func evaluate(_ js: String, context: Context) -> Any? { nil }
}

#endif

// MARK: - JSON 序列化

enum JSONTool {
    static func object(from string: String) -> Any? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func string(from object: Any?) -> String {
        guard let object = object else { return "" }
        if let s = object as? String { return s }
        if JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object, options: []),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\(object)"
    }

    static func prettyString(from object: Any?) -> String {
        guard let object = object else { return "" }
        if JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .withoutEscapingSlashes]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\(object)"
    }
}

// MARK: - 纯 Swift MD5

enum MD5 {
    static func hash(_ input: String) -> String {
        let message = Array(input.utf8)
        var a0: UInt32 = 0x67452301
        var b0: UInt32 = 0xefcdab89
        var c0: UInt32 = 0x98badcfe
        var d0: UInt32 = 0x10325476

        var messageBits = UInt64(message.count) * 8
        var padded = message
        padded.append(0x80)
        while padded.count % 64 != 56 { padded.append(0) }
        for i in 0..<8 {
            padded.append(UInt8((messageBits >> (8 * UInt64(i))) & 0xff))
        }
        messageBits = 0

        let s: [UInt32] = [
            7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
            5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
            4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
            6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
        ]
        var k = [UInt32](repeating: 0, count: 64)
        for i in 0..<64 {
            k[i] = UInt32(abs(sin(Double(i + 1))) * 4294967296.0)
        }

        var offset = 0
        while offset < padded.count {
            var m = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let base = offset + i * 4
                m[i] = UInt32(padded[base])
                    | (UInt32(padded[base + 1]) << 8)
                    | (UInt32(padded[base + 2]) << 16)
                    | (UInt32(padded[base + 3]) << 24)
            }
            var a = a0, b = b0, c = c0, d = d0
            for i in 0..<64 {
                var f: UInt32
                var g: Int
                if i < 16 {
                    f = (b & c) | (~b & d)
                    g = i
                } else if i < 32 {
                    f = (d & b) | (~d & c)
                    g = (5 * i + 1) % 16
                } else if i < 48 {
                    f = b ^ c ^ d
                    g = (3 * i + 5) % 16
                } else {
                    f = c ^ (b | ~d)
                    g = (7 * i) % 16
                }
                f = f &+ a &+ k[i] &+ m[g]
                a = d
                d = c
                c = b
                b = b &+ ((f << s[i]) | (f >> (32 - s[i])))
            }
            a0 = a0 &+ a
            b0 = b0 &+ b
            c0 = c0 &+ c
            d0 = d0 &+ d
            offset += 64
        }

        func hex(_ value: UInt32) -> String {
            var v = value.littleEndian
            var out = ""
            for _ in 0..<4 {
                out += String(format: "%02x", UInt8(v & 0xff))
                v >>= 8
            }
            return out
        }
        return hex(a0) + hex(b0) + hex(c0) + hex(d0)
    }
}

