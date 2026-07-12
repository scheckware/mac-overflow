import MacOverflowCore
import SwiftUI

/// A window listing every menu bar extra on the system, grouped into hidden and
/// visible. A far more useful view than System Settings, which only lists
/// Apple's own Control Center modules.
struct AllItemsView: View {
    @ObservedObject var monitor: MenuBarMonitor

    var body: some View {
        let hidden = monitor.allItems.filter { !$0.isVisibleInBar }
        let visible = monitor.allItems.filter { $0.isVisibleInBar }

        List {
            Section("Hidden (\(hidden.count))") {
                if hidden.isEmpty {
                    Text(monitor.isScanning ? "Scanning…" : "None")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(hidden) { row($0) }
                }
            }
            Section("In Menu Bar (\(visible.count))") {
                ForEach(visible) { row($0) }
            }
        }
        .frame(minWidth: 340, minHeight: 420)
        .toolbar {
            Button {
                monitor.refresh()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
        }
    }

    private func row(_ item: MenuBarItem) -> some View {
        Button {
            item.performClick()
            // The item may open a panel or quit its app — refresh shortly after.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                monitor.refresh()
            }
        } label: {
            HStack(spacing: 10) {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                } else {
                    Image(systemName: "circle.dashed")
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).lineLimit(1)
                    if item.title != item.ownerName {
                        Text(item.ownerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to activate \(item.title)")
    }
}
