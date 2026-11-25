import Foundation

enum URLTool {
    /// 把相对地址拼到 base 上；base 为空或地址本身是绝对地址时原样返回
    static func absolute(base: String?, _ relative: String) -> String {
        let r = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isEmpty { return base ?? "" }
        if r.hasPrefix("data:") || r.hasPrefix("blob:") { return r }
        if r.hasPrefix("//") {
            if let scheme = base?.split(separator: ":").first, !scheme.isEmpty {
                return "\(scheme):\(r)"
            }
            return "https:\(r)"
        }
        if let scheme = URL(string: r)?.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return r
        }
        guard let base = base, !base.isEmpty else { return r }
        guard let baseURL = URL(string: base) else { return r }
        if let resolved = URL(string: r, relativeTo: baseURL)?.absoluteURL,
           !resolved.absoluteString.isEmpty {
            return resolved.absoluteString
        }
        return r
    }

    /// 对 URL 里的非 ASCII 字符、空格进行百分号编码，已编码的部分保持原样
    static func encode(_ url: String) -> String {
        var out = ""
        out.reserveCapacity(url.count)
        var chars = Array(url)
        var i = 0
        let allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" +
            "-._~:/?#[]@!$&'()*+,;=%"
        let allowedSet = Set(allowed)
        while i < chars.count {
            let c = chars[i]
            if c == "%" && i + 2 < chars.count,
               chars[i + 1].isHexDigit, chars[i + 2].isHexDigit {
                out.append(c)
                out.append(chars[i + 1])
                out.append(chars[i + 2])
                i += 3
                continue
            }
            if allowedSet.contains(c) {
                out.append(c)
            } else {
                for byte in String(c).utf8 {
                    out += String(format: "%%%02X", byte)
                }
            }
            i += 1
        }
        return out
    }

    /// 解析书源的 header 字段（JSON 对象）以及登录头
    static func headers(fromJSON raw: String?) -> [String: String] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let data = raw.data(using: .utf8) else { return [:] }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var out: [String: String] = [:]
            for (k, v) in obj {
                if let s = v as? String { out[k] = s }
                else { out[k] = "\(v)" }
            }
            return out
        }
        // 兼容 "key:value\nkey:value" 的写法
        var out: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let k = parts[0].trimmingCharacters(in: .whitespaces)
                let v = parts[1].trimmingCharacters(in: .whitespaces)
                if !k.isEmpty { out[k] = v }
            }
        }
        return out
    }

    static func host(_ url: String) -> String? {
        URL(string: url)?.host
    }

    /// 站点根地址，用于 Referer
    static func origin(_ url: String) -> String {
        guard let u = URL(string: url), let scheme = u.scheme, let host = u.host else {
            return url
        }
        var s = "\(scheme)://\(host)"
        if let port = u.port { s += ":\(port)" }
        return s
    }

    static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private extension Character {
    var isHexDigit: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
