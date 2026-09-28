import SwiftUI

/// Lets the user choose which prompt categories are eligible for the random prompt.
/// At least one category must always remain selected.
struct PromptCategoryPickerView: View {
    @Binding var selection: Set<PromptCategory>

    var body: some View {
        List {
            Section {
                ForEach(PromptCategory.allCases) { category in
                    row(for: category)
                }
            } footer: {
                Text("Prompts are drawn only from the categories you enable. At least one category must stay on.")
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for category: PromptCategory) -> some View {
        let isOn = selection.contains(category)
        return Button {
            toggle(category)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: category.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26)
                Text(category.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func toggle(_ category: PromptCategory) {
        var updated = selection
        if updated.contains(category) {
            guard updated.count > 1 else { return }
            updated.remove(category)
        } else {
            updated.insert(category)
        }
        selection = updated
    }
}
