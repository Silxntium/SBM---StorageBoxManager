import SwiftUI

struct TransfersPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.transfers.transfers.isEmpty {
                    ContentUnavailableView(
                        "No Transfers",
                        systemImage: "arrow.up.arrow.down.circle",
                        description: Text("Uploads and downloads will show up here.")
                    )
                } else {
                    List(model.transfers.transfers) { transfer in
                        TransferRow(
                            transfer: transfer,
                            onCancel: { model.transfers.cancel(transfer.id) },
                            onRetry: { model.transfers.retry(transfer.id) }
                        )
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Transfers")
            .toolbar {
                if model.transfers.hasRetryableTransfers {
                    ToolbarItem(placement: .automatic) {
                        Button("Retry Failed") { model.transfers.retryAllFailed() }
                            .help("Retry failed and cancelled transfers")
                    }
                }
                if model.transfers.activeCount > 0 {
                    ToolbarItem(placement: .automatic) {
                        Button("Cancel All") { model.transfers.cancelAll() }
                    }
                }
                if model.transfers.hasFinishedEntries {
                    ToolbarItem(placement: .automatic) {
                        Button("Clear") { model.transfers.clearFinished() }
                            .help("Remove finished transfers")
                    }
                }
            }
        }
    }
}

private struct TransferRow: View {
    let transfer: Transfer
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(symbolColor)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(transfer.name)
                        .font(.body)
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

                HStack {
                    Text(transfer.progressDescription)
                        .font(.caption)
                        .foregroundStyle(isFailed ? Color.red : .secondary)
                        .lineLimit(2)
                    if let fraction = transfer.fractionCompleted, transfer.state == .running {
                        Spacer(minLength: 8)
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if let rate = transfer.rateDescription {
                    Text(rate)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if transfer.canRetry {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Retry")
                .accessibilityLabel("Retry \(transfer.name)")
            } else if transfer.state.isActive {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Cancel")
                .accessibilityLabel("Cancel \(transfer.name)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if transfer.canRetry {
                Button("Retry", action: onRetry)
            } else if transfer.state.isActive {
                Button("Cancel", role: .destructive, action: onCancel)
            }
        }
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
