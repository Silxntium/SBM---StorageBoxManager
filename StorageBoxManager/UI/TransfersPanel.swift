import SwiftUI

/// Collapsible strip at the bottom of the window showing what is currently moving.
struct TransfersPanel: View {
    @Environment(AppModel.self) private var model
    @State private var isExpanded = true

    var body: some View {
        let queue = model.transfers

        if !queue.transfers.isEmpty {
            VStack(spacing: 0) {
                Divider()
                header(queue)
                if isExpanded {
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(queue.transfers) { transfer in
                                TransferRow(transfer: transfer) { queue.cancel(transfer.id) }
                                Divider().padding(.leading, 34)
                            }
                        }
                    }
                    .frame(maxHeight: 170)
                }
            }
            .background(.bar)
        }
    }

    private func header(_ queue: TransferQueue) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Text(queue.activeCount > 0
                 ? "\(queue.activeCount) Übertragung\(queue.activeCount == 1 ? "" : "en") aktiv"
                 : "Übertragungen")
                .font(.callout.weight(.medium))

            if queue.activeCount > 0 {
                ProgressView().controlSize(.small)
            }

            Spacer()

            if queue.activeCount > 0 {
                Button("Alle abbrechen") { queue.cancelAll() }
                    .buttonStyle(.accessoryBar)
            }
            if queue.hasFinishedEntries {
                Button("Liste leeren") { queue.clearFinished() }
                    .buttonStyle(.accessoryBar)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct TransferRow: View {
    let transfer: Transfer
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(transfer.name)
                        .lineLimit(1)
                    Text(transfer.boxName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if transfer.state == .running || transfer.state == .waiting {
                    if let fraction = transfer.fractionCompleted {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }

                Text(transfer.progressDescription)
                    .font(.caption)
                    .foregroundStyle(isFailed ? .red : .secondary)
                    .lineLimit(1)
            }

            if transfer.state.isActive {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Abbrechen")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var isFailed: Bool {
        if case .failed = transfer.state { return true }
        return false
    }

    private var symbolName: String {
        switch transfer.state {
        case .finished: "checkmark.circle.fill"
        case .cancelled: "slash.circle"
        case .failed: "exclamationmark.triangle.fill"
        case .waiting, .running: transfer.kind.symbolName
        }
    }

    private var symbolColor: Color {
        switch transfer.state {
        case .finished: .green
        case .failed: .red
        case .cancelled: .secondary
        case .waiting, .running: .accentColor
        }
    }
}
