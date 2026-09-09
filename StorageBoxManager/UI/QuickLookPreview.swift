import AppKit
import Quartz

enum QuickLookPreview {
    @MainActor
    static func present(url: URL, title: String) {
        Coordinator.shared.present(url: url, title: title)
    }
}

@MainActor
private final class Coordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = Coordinator()

    private var item: FilePreviewItem?

    func present(url: URL, title: String) {
        item = FilePreviewItem(url: url, title: title)
        guard let panel = QLPreviewPanel.shared() else {
            NSWorkspace.shared.open(url)
            return
        }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        MainActor.assumeIsolated { item == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> any QLPreviewItem {
        MainActor.assumeIsolated { item ?? FilePreviewItem(url: URL(fileURLWithPath: "/dev/null"), title: "") }
    }
}

private final class FilePreviewItem: NSObject, QLPreviewItem, @unchecked Sendable {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, title: String) {
        previewItemURL = url
        previewItemTitle = title
    }
}
