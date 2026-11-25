import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - 请求 / 响应

struct HTTPRequest {
    var url: String
    var method: String = "GET"
    var headers: [String: String] = [:]
    var body: Data?
    var timeout: TimeInterval = 20
}

struct HTTPResponse {
    var url: URL
    var statusCode: Int
    var data: Data
    var headers: [String: String]
    var text: String

    var isSuccess: Bool { (200..<400).contains(statusCode) }
}

enum HTTPError: LocalizedError {
    case badURL(String)
    case emptyBody(String)
    case status(Int, String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let u): return "链接无效：\(u)"
        case .emptyBody(let u): return "内容为空：\(u)"
        case .status(let c, let u): return "HTTP \(c)：\(u)"
        case .network(let m): return m
        }
    }
}

// MARK: - 客户端

final class HTTPClient {
    static let shared = HTTPClient()

    /// 默认 UA，尽量贴近桌面浏览器，减少被站点拦截的概率
    static let defaultUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url), let scheme = url.scheme,
              scheme == "http" || scheme == "https" else {
            throw HTTPError.badURL(request.url)
        }
        var req = URLRequest(url: url, timeoutInterval: request.timeout)
        req.httpMethod = request.method
        req.httpBody = request.body
        if req.value(forHTTPHeaderField: "User-Agent") == nil {
            req.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        }
        for (k, v) in request.headers where !k.isEmpty {
            req.setValue(v, forHTTPHeaderField: k)
        }
        if req.value(forHTTPHeaderField: "Accept") == nil {
            req.setValue(
                "text/html,application/xhtml+xml,application/xml;q=0.9," +
                "application/json;q=0.9,*/*;q=0.8",
                forHTTPHeaderField: "Accept")
        }
        if req.value(forHTTPHeaderField: "Accept-Language") == nil {
            req.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw HTTPError.network("请求失败：\(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.network("无效响应")
        }
        var headerMap: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            if let key = k as? String, let val = v as? String {
                headerMap[key] = val
            }
        }
        if !(200..<400).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode, request.url)
        }
        let charset = charsetFromHeaders(headerMap)
        let text = DataDecoder.decode(data: data, charsetName: charset)
        let finalURL = http.url ?? url
        return HTTPResponse(
            url: finalURL,
            statusCode: http.statusCode,
            data: data,
            headers: headerMap,
            text: text
        )
    }

    /// JS 里的 java.ajax 是同步调用，这里用信号量包一层
    func sendSync(_ request: HTTPRequest) -> String? {
        var result: String?
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let resp = try await self.send(request)
                result = resp.text
            } catch {
                result = nil
            }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + request.timeout + 5) == .timedOut {
            return nil
        }
        return result
    }

    private func charsetFromHeaders(_ headers: [String: String]) -> String? {
        for (k, v) in headers where k.lowercased() == "content-type" {
            if let range = v.range(of: "charset=", options: .caseInsensitive) {
                let raw = v[range.upperBound...]
                let name = raw.split(whereSeparator: { $0 == ";" || $0 == " " }).first
                if let name = name, !name.isEmpty {
                    return String(name).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            }
        }
        return nil
    }
}

// MARK: - 编码识别

enum DataDecoder {
    /// 依次尝试：响应头 charset -> HTML meta charset -> UTF-8 -> GB18030
    static func decode(data: Data, charsetName: String? = nil) -> String {
        if let name = charsetName, let enc = encoding(named: name),
           let text = String(data: data, encoding: enc) {
            return text
        }
        if let metaCharset = sniffMetaCharset(data), let enc = encoding(named: metaCharset),
           let text = String(data: data, encoding: enc) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let enc = encoding(named: "gb18030"), let text = String(data: data, encoding: enc) {
            return text
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    static func encoding(named name: String) -> String.Encoding? {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "", "utf-8", "utf8", "unicode-1-1-utf-8":
            return .utf8
        case "gbk", "gb2312", "gb-2312", "gb18030", "gb_2312-80", "x-gbk":
            return gb18030
        case "big5", "big-5", "big5-hkscs":
            return big5
        case "iso-8859-1", "latin1", "windows-1252":
            return .isoLatin1
        case "utf-16", "utf-16le":
            return .utf16LittleEndian
        case "utf-16be":
            return .utf16BigEndian
        default:
            #if canImport(Darwin)
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(key as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                return String.Encoding(rawValue: nsEncoding)
            }
            #endif
            return nil
        }
    }

    private static var gb18030: String.Encoding? {
        let cf = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let ns = CFStringConvertEncodingToNSStringEncoding(cf)
        return ns == kCFStringEncodingInvalidId ? nil : String.Encoding(rawValue: ns)
    }

    private static var big5: String.Encoding? {
        let cf = CFStringEncoding(CFStringEncodings.big5.rawValue)
        let ns = CFStringConvertEncodingToNSStringEncoding(cf)
        return ns == kCFStringEncodingInvalidId ? nil : String.Encoding(rawValue: ns)
    }

    /// 从 HTML 头部读取 meta charset
    static func sniffMetaCharset(_ data: Data) -> String? {
        let prefix = data.prefix(4096)
        guard let head = String(data: prefix, encoding: .isoLatin1) else { return nil }
        let lower = head.lowercased()
        if let r = lower.range(of: "charset=") {
            let sub = head[r.upperBound...]
            var name = ""
            for ch in sub {
                if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                    name.append(ch)
                } else {
                    break
                }
            }
            if !name.isEmpty { return name }
        }
        return nil
    }
}
