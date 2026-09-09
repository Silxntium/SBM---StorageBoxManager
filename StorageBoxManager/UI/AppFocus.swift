import SwiftUI

struct BrowserActions {
    var goUp: () -> Void = {}
    var canGoUp = false
    var goBack: () -> Void = {}
    var canGoBack = false
    var goForward: () -> Void = {}
    var canGoForward = false
    var goToFolder: () -> Void = {}
    var newFolder: () -> Void = {}
    var upload: () -> Void = {}
    var download: () -> Void = {}
    var downloadAndOpen: () -> Void = {}
    var canDownload = false
    var deleteSelection: () -> Void = {}
    var canDelete = false
    var refresh: () -> Void = {}
    var toggleHiddenFiles: () -> Void = {}
    var showsHiddenFiles = false
    var selectAll: () -> Void = {}
    var getInfo: () -> Void = {}
    var canGetInfo = false
    var quickLook: () -> Void = {}
    var canQuickLook = false
    var duplicate: () -> Void = {}
    var canDuplicate = false
    var toggleFavorite: () -> Void = {}
    var isFavorite = false
    var setLayout: (ListingLayout) -> Void = { _ in }
    var layout: ListingLayout = .list
    var setSort: (SortField) -> Void = { _ in }
    var sortField: SortField = .name
    var toggleFoldersFirst: () -> Void = {}
    var foldersFirst = true
    var toggleRelativeDates: () -> Void = {}
    var usesRelativeDates = true
    var focusSearch: () -> Void = {}
}

extension FocusedValues {
    @Entry var appModel: AppModel?
    @Entry var browserActions: BrowserActions?
}
