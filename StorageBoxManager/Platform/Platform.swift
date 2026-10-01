import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The handful of places where AppKit and UIKit disagree. Everything platform-specific in the
// app should end up funnelled through here rather than sprinkling #if through the views.

func copyToPasteboard(_ string: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
    #else
    UIPasteboard.general.string = string
    #endif
}

#if os(macOS)
/// Hands a downloaded file to whatever app owns it. iOS has no equivalent — there the file gets
/// shown in Quick Look instead, see `AppModel.presentPreview`.
@MainActor
func openInDefaultApp(_ url: URL) {
    NSWorkspace.shared.open(url)
}
#endif

extension Color {
    /// Background behind a full-window placeholder (loading, error, empty folder).
    static var platformWindowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    /// Background behind scrollable file content.
    static var platformContentBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

extension View {
    /// `navigationSubtitle` is macOS-only below iOS 26, and the iPhone navigation bar has no room
    /// for a subtitle anyway — the path bar at the bottom already says where you are.
    @ViewBuilder
    func platformNavigationSubtitle(_ subtitle: String) -> some View {
        #if os(macOS)
        navigationSubtitle(subtitle)
        #else
        self
        #endif
    }

    /// ⌫ on a selection. macOS delivers it as a command; on iOS the equivalent is a swipe.
    @ViewBuilder
    func onDeleteKey(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onDeleteCommand(perform: action)
        #else
        self
        #endif
    }

    /// Esc while editing a field inline.
    @ViewBuilder
    func onEscapeKey(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }

    /// ⌘C on a selection. iOS copies through the context menu instead.
    @ViewBuilder
    func onCopyKey(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onCopyCommand { action(); return [] }
        #else
        self
        #endif
    }

    /// Sheets need explicit sizing on macOS and must stay flexible on iOS.
    @ViewBuilder
    func sheetFrame(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        frame(width: width, height: height)
        #else
        self
        #endif
    }

    @ViewBuilder
    func sheetFrame(minWidth: CGFloat, idealWidth: CGFloat? = nil, minHeight: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: minWidth, idealWidth: idealWidth, minHeight: minHeight)
        #else
        self
        #endif
    }
}
