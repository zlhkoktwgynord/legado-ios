import SwiftUI

/// 「阅读统计」：按最近阅读时间统计，不做估算
struct ReadRecordView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("阅读统计")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(LegadoTheme.primaryText(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)

                    HStack(spacing: 12) {
                        metricCard("在读书籍", "\(readingCount)", "本")
                        metricCard("书架总数", "\(model.books.count)", "本")
                        metricCard("启用书源", "\(model.enabledSources.count)", "个")
                    }

                    weekChart

                    recentList

                    Text("统计依据每本书最近一次阅读时间，仅保存在本机。")
                        .font(.system(size: 11))
                        .foregroundColor(LegadoTheme.tertiaryText(scheme))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .background(LegadoTheme.background(scheme).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var readingCount: Int {
        model.books.filter { $0.durChapterIndex > 0 || $0.durChapterTime > 0 }.count
    }

    private func metricCard(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(LegadoTheme.secondaryText(scheme))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(LegadoTheme.primaryText(scheme))
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundColor(LegadoTheme.secondaryText(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LegadoTheme.card(scheme))
        )
    }

    /// 最近 7 天每天接触过的书数
    private var weekData: [(label: String, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [(String, Int)] = []
        let labels = ["日", "一", "二", "三", "四", "五", "六"]
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let count = model.books.filter { book in
                guard book.durChapterTime > 0 else { return false }
                let date = Date(timeIntervalSince1970: Double(book.durChapterTime) / 1000)
                return date >= day && date < next
            }.count
            let weekday = calendar.component(.weekday, from: day) - 1
            result.append((label: labels[max(0, min(6, weekday))], count: count))
        }
        return result
    }

    private var weekChart: some View {
        let data = weekData
        let peak = max(1, data.map { $0.count }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("最近 7 天")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(LegadoTheme.secondaryText(scheme))
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 6) {
                        Text(item.count > 0 ? "\(item.count)" : "")
                            .font(.system(size: 10))
                            .foregroundColor(LegadoTheme.secondaryText(scheme))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(item.count > 0
                                  ? LegadoTheme.accent.opacity(0.75)
                                  : LegadoTheme.fill(scheme))
                            .frame(height: max(6, CGFloat(item.count) / CGFloat(peak) * 96))
                        Text(item.label)
                            .font(.system(size: 11))
                            .foregroundColor(LegadoTheme.secondaryText(scheme))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LegadoTheme.card(scheme))
        )
    }

    private var recentList: some View {
        let recent = model.books
            .filter { $0.durChapterTime > 0 }
            .sorted { $0.durChapterTime > $1.durChapterTime }
            .prefix(5)

        return VStack(alignment: .leading, spacing: 0) {
            Text("最近在读")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(LegadoTheme.secondaryText(scheme))
                .padding(.bottom, 8)

            if recent.isEmpty {
                Text("还没有阅读记录")
                    .font(.system(size: 13))
                    .foregroundColor(LegadoTheme.tertiaryText(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LegadoTheme.card(scheme))
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent)) { book in
                        HStack(spacing: 12) {
                            Color.clear
                                .frame(width: 40, height: 54)
                                .overlay(RemoteImage(urlString: book.customCoverUrl ?? book.coverUrl ?? ""))
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(book.name)
                                    .font(.system(size: 15))
                                    .foregroundColor(LegadoTheme.primaryText(scheme))
                                    .lineLimit(1)
                                Text(book.durChapterTitle ?? "未开始")
                                    .font(.system(size: 12))
                                    .foregroundColor(LegadoTheme.secondaryText(scheme))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(timeText(book.durChapterTime))
                                .font(.system(size: 11))
                                .foregroundColor(LegadoTheme.tertiaryText(scheme))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        if book.id != recent.last?.id {
                            LegadoDivider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LegadoTheme.card(scheme))
                )
            }
        }
    }

    private func timeText(_ millis: Int64) -> String {
        guard millis > 0 else { return "" }
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "今天 " + formatter.string(from: date)
        }
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}
