import SwiftUI

#if os(macOS)
import AppKit
import Quartz
#else
import QuickLook
#endif

struct QuickLookRequest: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let title: String
}

#if os(macOS)

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

#else

// iOS has no floating panel, so the preview is a sheet the browser presents. Hosting the
// controller costs us its own navigation bar, so the share button - the way to keep a copy
// somewhere else - is put back explicitly.
struct QuickLookSheet: View {
    let request: QuickLookRequest

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuickLookView(url: request.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(request.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: request.url)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}

#endif
