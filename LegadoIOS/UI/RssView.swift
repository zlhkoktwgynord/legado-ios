import SwiftUI

/// 「RSS」页：订阅还没有移植，先做成占位说明
struct RssView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("RSS")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(LegadoTheme.primaryText(scheme))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)

            Spacer()

            VStack(spacing: 14) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(LegadoTheme.tertiaryText(scheme))
                Text("RSS 订阅还没移植")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(LegadoTheme.primaryText(scheme))
                Text("安卓版的 RSS 源、文章列表和离线缓存留在后续版本。\n现在可以先用「书源」搜书和看小说。")
                    .font(.system(size: 13))
                    .foregroundColor(LegadoTheme.secondaryText(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LegadoTheme.background(scheme).ignoresSafeArea())
    }
}
