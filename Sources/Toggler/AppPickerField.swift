import AppKit
import SwiftUI

/// A button that shows the currently chosen application and opens a searchable
/// popover of installed apps. The selected app's stable target value (bundle
/// id or path) is written to `appTarget`.
struct AppPickerField: View {
    @Binding var appTarget: String
    @ObservedObject var appsModel: InstalledAppsModel

    @State private var isPresented = false
    @State private var search = ""

    private var currentEntry: InstalledApp {
        appsModel.entry(forStoredRawValue: appTarget)
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                icon(for: currentEntry)
                    .frame(width: 18, height: 18)
                Text(currentEntry.name.isEmpty ? "Choose app…" : currentEntry.name)
                    .foregroundStyle(currentEntry.name.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search apps", text: $search)
                .textFieldStyle(.roundedBorder)

            List(filteredApps) { app in
                Button {
                    appTarget = app.targetRawValue
                    isPresented = false
                    search = ""
                } label: {
                    HStack(spacing: 6) {
                        icon(for: app)
                            .frame(width: 18, height: 18)
                        Text(app.name).lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .frame(width: 280, height: 320)
        }
        .padding(10)
        .onAppear { appsModel.load() }
    }

    private var filteredApps: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appsModel.apps }
        return appsModel.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder
    private func icon(for app: InstalledApp) -> some View {
        if app.path.isEmpty {
            Image(systemName: "app.dashed")
                .resizable()
                .foregroundStyle(.secondary)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
        }
    }
}
