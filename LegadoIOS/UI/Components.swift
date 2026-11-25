import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 颜色

extension Color {
    init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 {
            var expanded = ""
            for ch in text { expanded.append(ch); expanded.append(ch) }
            text = expanded
        }
        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - 封面

final class CoverLoader: ObservableObject {
    @Published var image: UIImage?
    private var task: URLSessionDataTask?
    private static let cache = NSCache<NSString, UIImage>()

    func load(_ urlString: String, headers: [String: String] = [:]) {
        guard !urlString.isEmpty else { return }
        let key = urlString as NSString
        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(HTTPClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        }
        if request.value(forHTTPHeaderField: "Referer") == nil {
            request.setValue(URLTool.origin(urlString), forHTTPHeaderField: "Referer")
        }
        task = URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            Self.cache.setObject(image, forKey: key)
            DispatchQueue.main.async { self?.image = image }
        }
        task?.resume()
    }

    deinit { task?.cancel() }
}

struct RemoteImage: View {
    let urlString: String
    var headers: [String: String] = [:]
    @StateObject private var loader = CoverLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(
                        Image(systemName: "book.closed")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary.opacity(0.6))
                    )
            }
        }
        .onAppear {
            loader.load(urlString, headers: headers)
        }
    }
}

struct BookCover: View {
    var url: String?
    var title: String
    var width: CGFloat = 80
    var height: CGFloat = 110
    var radius: CGFloat = 6

    var body: some View {
        Group {
            if let url = url, !url.isEmpty {
                RemoteImage(urlString: url)
            } else {
                ZStack {
                    LinearGradient(colors: [Color.accentColor.opacity(0.75),
                                            Color.accentColor.opacity(0.45)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                    Text(title)
                        .font(.system(size: max(10, width / 6), weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(4)
                        .multilineTextAlignment(.center)
                        .padding(6)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
    }
}

// MARK: - 小组件

struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12))
            .foregroundColor(.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.headline)
            if let message = message {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingRow: View {
    var text: String = "加载中…"

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text).font(.footnote).foregroundColor(.secondary)
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.footnote)
            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
