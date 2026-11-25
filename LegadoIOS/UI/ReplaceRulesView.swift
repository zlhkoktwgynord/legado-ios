import SwiftUI

/// 替换净化规则管理
struct ReplaceRulesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: ReplaceRule?

    var body: some View {
        List {
            Section {
                Text("按顺序应用到正文，支持正则。比如把「本章未完」「请记住本站」这类广告行删掉。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section {
                ForEach(model.replaceRules) { rule in
                    Toggle(isOn: Binding(
                        get: { rule.enabled },
                        set: { model.setReplaceRule(rule, enabled: $0) })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.name.isEmpty ? "未命名规则" : rule.name)
                                .font(.subheadline)
                            Text(rule.pattern)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            if let index = model.replaceRules.firstIndex(where: { $0.id == rule.id }) {
                                model.deleteReplaceRules(at: IndexSet(integer: index))
                            }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            editing = rule
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            } header: {
                Text("规则（\(model.replaceRules.count)）")
            } footer: {
                Text("左滑可以编辑或删除；关闭开关即临时停用。")
            }

            Section {
                Button {
                    editing = ReplaceRule()
                } label: {
                    Label("添加规则", systemImage: "plus")
                }
            }
        }
        .navigationTitle("替换净化")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { rule in
            ReplaceRuleEditor(rule: rule)
        }
    }
}

struct ReplaceRuleEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var rule: ReplaceRule

    init(rule: ReplaceRule) {
        _rule = State(initialValue: rule)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如：去掉广告", text: $rule.name)
                }
                Section {
                    TextField("要匹配的内容", text: $rule.pattern)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("替换成（留空即删除）", text: $rule.replacement)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("匹配与替换")
                } footer: {
                    Text("用正则时可以用 ( ) 分组、用 $1 引用分组。")
                }
                Section {
                    Toggle("按正则处理", isOn: $rule.isRegex)
                    Toggle("启用", isOn: $rule.enabled)
                }
            }
            .navigationTitle(rule.name.isEmpty ? "净化规则" : rule.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        model.upsertReplaceRule(rule)
                        dismiss()
                    }
                    .disabled(rule.pattern.isEmpty)
                }
            }
        }
    }
}
