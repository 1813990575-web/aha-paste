import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appDelegate: AppDelegate
    @EnvironmentObject private var settings: AppSettings

    @State private var selectedFilter: ClipFilter = .all
    @State private var searchText = ""
    @State private var composerText = ""
    @State private var composerNote = ""
    @State private var pendingImage: NSImage?
    @State private var errorMessage: String?
    @State private var refreshToken = UUID()
    @State private var newTagName = ""
    @State private var isCreateTagSheetPresented = false
    @State private var isImageDropTargeted = false
    @State private var tagPendingRename: Tag?
    @State private var tagPendingDelete: Tag?
    @State private var renameTagName = ""
    @State private var isSettingsPresented = false
    @State private var itemPendingEdit: ClipItem?
    @State private var editingContentText = ""
    @State private var editingNoteText = ""
    @State private var toastMessage: String?
    @State private var isToastVisible = false
    @State private var composerContentFocusID = 0
    @State private var composerNoteFocusID = 0
    @State private var draggedItemID: UUID?
    @State private var itemDropIndicator: ClipItemDropIndicator?
    @State private var itemRowHeights: [UUID: CGFloat] = [:]
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var draggedItemOffset: CGSize = .zero

    var body: some View {
        let store = ClipStore(context: modelContext)
        let loadedData = loadData(store: store)
        let items = loadedData.items
        let customTags = loadedData.customTags
        let customTagCounts = loadedData.customTagCounts

        VStack(spacing: 0) {
            header
            searchBar
            filterBar(store: store, customTags: customTags, counts: customTagCounts)
            Divider()
            itemsList(store: store, items: items, customTags: customTags)
            Divider()
            composer(store: store, loadErrorMessage: loadedData.errorMessage)
        }
        .background(Color.clear)
        .id(refreshToken)
        .sheet(isPresented: $isCreateTagSheetPresented) { createTagSheet(store: store) }
        .sheet(item: $tagPendingRename) { tag in renameTagSheet(store: store, tag: tag) }
        .sheet(item: $itemPendingEdit) { item in editItemSheet(store: store, item: item) }
        .alert("删除分类？", isPresented: Binding(
            get: { tagPendingDelete != nil },
            set: { if $0 == false { tagPendingDelete = nil } }
        )) {
            Button("取消", role: .cancel) {
                tagPendingDelete = nil
            }
            Button("删除", role: .destructive) {
                guard let tagPendingDelete else { return }
                try? store.deleteTag(tagPendingDelete)
                if selectedFilter == .tag(tagPendingDelete.id) {
                    selectedFilter = .all
                }
                self.tagPendingDelete = nil
                refreshToken = UUID()
            }
        } message: {
            Text("删除后，该分类会从列表中移除。")
        }
        .overlay(alignment: .bottom) {
            if isToastVisible, let toastMessage {
                Text(toastMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.72))
                    )
                    .padding(.bottom, 78)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            resizeHandle
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isToastVisible)
        .onAppear {
            requestComposerFocus()
        }
        .onChange(of: pendingImage != nil) { _, _ in
            requestComposerFocus()
        }
    }

    private func itemsList(store: ClipStore, items: [ClipItem], customTags: [Tag]) -> some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(items, id: \.id) { item in
                        clipRow(store: store, item: item, customTags: customTags)
                            .onGeometryChange(for: CGFloat.self) { geometry in
                                geometry.size.height
                            } action: { newHeight in
                                itemRowHeights[item.id] = newHeight
                            }
                            .onGeometryChange(for: CGRect.self) { geometry in
                                geometry.frame(in: .named("clip-items-list"))
                            } action: { newFrame in
                                itemFrames[item.id] = newFrame
                            }
                            .opacity(draggedItemID == item.id ? 0.001 : 1)
                            .overlay(alignment: .top) {
                                if itemDropIndicator?.itemID == item.id, itemDropIndicator?.placement == .before {
                                    clipDropInsertionLine
                                        .offset(y: -8)
                                }
                            }
                            .overlay(alignment: .bottom) {
                                if itemDropIndicator?.itemID == item.id, itemDropIndicator?.placement == .after {
                                    clipDropInsertionLine
                                        .offset(y: 8)
                                }
                            }
                            .animation(.spring(response: 0.22, dampingFraction: 0.9), value: draggedItemID)
                            .animation(.spring(response: 0.22, dampingFraction: 0.9), value: itemDropIndicator)
                            .simultaneousGesture(itemReorderGesture(for: item, items: items, store: store))
                    }
                }
                .padding(16)
            }
            if let draggedItemID,
               let item = items.first(where: { $0.id == draggedItemID }),
               let frame = itemFrames[draggedItemID] {
                clipRow(store: store, item: item, customTags: customTags)
                    .frame(width: frame.width)
                    .scaleEffect(0.985)
                    .shadow(color: Color.black.opacity(0.16), radius: 16, y: 8)
                    .offset(x: frame.minX + 18, y: frame.minY)
                    .offset(draggedItemOffset)
                    .allowsHitTesting(false)
                    .zIndex(20)
            }
        }
        .coordinateSpace(name: "clip-items-list")
    }

    private func clipRow(store: ClipStore, item: ClipItem, customTags: [Tag]) -> some View {
        ClipRowView(
            item: item,
            availableTags: customTags,
            currentTag: store.currentCustomTag(for: item)
        ) {
            store.copyPayload(for: item)
            showCopyFeedback()
        } onDelete: {
            try? store.delete(item)
            refreshToken = UUID()
        } onEdit: {
            editingContentText = item.contentText ?? ""
            editingNoteText = item.note
            itemPendingEdit = item
        } onTagChange: { tag in
            try? store.assignCustomTag(tag, to: item)
            refreshToken = UUID()
        }
    }

    private var clipDropInsertionLine: some View {
        Capsule(style: .continuous)
            .fill(Color.accentColor.opacity(0.95))
            .frame(height: 3)
            .padding(.horizontal, 6)
            .shadow(color: Color.accentColor.opacity(0.2), radius: 4, y: 1)
    }

    private func itemReorderGesture(for item: ClipItem, items: [ClipItem], store: ClipStore) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("clip-items-list"))
            .onChanged { value in
                if draggedItemID != item.id {
                    draggedItemID = item.id
                }
                draggedItemOffset = value.translation
                itemDropIndicator = resolveDropIndicator(
                    locationY: value.location.y,
                    draggingItemID: item.id,
                    items: items
                )
            }
            .onEnded { value in
                let indicator = resolveDropIndicator(
                    locationY: value.location.y,
                    draggingItemID: item.id,
                    items: items
                )

                if let indicator {
                    try? store.moveItem(item, to: indicator.targetIndex, in: items)
                }

                draggedItemID = nil
                draggedItemOffset = .zero
                itemDropIndicator = nil
            }
    }

    private func resolveDropIndicator(locationY: CGFloat, draggingItemID: UUID, items: [ClipItem]) -> ClipItemDropIndicator? {
        let orderedTargets = items
            .filter { $0.id != draggingItemID }
            .compactMap { item -> (ClipItem, CGRect)? in
                guard let frame = itemFrames[item.id] else { return nil }
                return (item, frame)
            }
            .sorted { lhs, rhs in
                lhs.1.minY < rhs.1.minY
            }

        guard orderedTargets.isEmpty == false else {
            return nil
        }

        if let first = orderedTargets.first, locationY <= first.1.minY {
            return makeDropIndicator(
                targetItemID: first.0.id,
                placement: .before,
                draggingItemID: draggingItemID,
                items: items
            )
        }

        if let last = orderedTargets.last, locationY >= last.1.maxY {
            return makeDropIndicator(
                targetItemID: last.0.id,
                placement: .after,
                draggingItemID: draggingItemID,
                items: items
            )
        }

        for (item, frame) in orderedTargets {
            if locationY >= frame.minY && locationY <= frame.maxY {
                let placement: ClipItemDropIndicator.Placement = locationY < frame.midY ? .before : .after
                return makeDropIndicator(
                    targetItemID: item.id,
                    placement: placement,
                    draggingItemID: draggingItemID,
                    items: items
                )
            }
        }

        for index in 0..<(orderedTargets.count - 1) {
            let current = orderedTargets[index]
            let next = orderedTargets[index + 1]
            if locationY > current.1.maxY && locationY < next.1.minY {
                return makeDropIndicator(
                    targetItemID: next.0.id,
                    placement: .before,
                    draggingItemID: draggingItemID,
                    items: items
                )
            }
        }

        return nil
    }

    private func makeDropIndicator(
        targetItemID: UUID,
        placement: ClipItemDropIndicator.Placement,
        draggingItemID: UUID,
        items: [ClipItem]
    ) -> ClipItemDropIndicator? {
        guard let sourceIndex = items.firstIndex(where: { $0.id == draggingItemID }),
              let targetIndex = items.firstIndex(where: { $0.id == targetItemID }) else {
            return nil
        }

        let proposedTargetIndex = placement == .before ? targetIndex : targetIndex + 1
        let boundedTargetIndex = min(max(proposedTargetIndex, 0), items.count)
        let adjustedTargetIndex = boundedTargetIndex > sourceIndex ? boundedTargetIndex - 1 : boundedTargetIndex

        guard adjustedTargetIndex != sourceIndex else {
            return nil
        }

        return ClipItemDropIndicator(
            itemID: targetItemID,
            placement: placement,
            targetIndex: adjustedTargetIndex
        )
    }

    private func createTagSheet(store: ClipStore) -> some View {
        CreateTagSheet(
            title: "新建分类",
            fieldPlaceholder: "输入分类名称",
            newTagName: $newTagName,
            onCreate: {
                try? store.createTag(named: newTagName)
                newTagName = ""
                isCreateTagSheetPresented = false
                refreshToken = UUID()
            },
            onCancel: {
                newTagName = ""
                isCreateTagSheetPresented = false
            }
        )
    }

    private func renameTagSheet(store: ClipStore, tag: Tag) -> some View {
        CreateTagSheet(
            title: "重命名分类",
            fieldPlaceholder: "输入新的分类名称",
            newTagName: $renameTagName,
            onCreate: {
                try? store.renameTag(tag, to: renameTagName)
                renameTagName = ""
                tagPendingRename = nil
                refreshToken = UUID()
            },
            onCancel: {
                renameTagName = ""
                tagPendingRename = nil
            }
        )
    }

    private func editItemSheet(store: ClipStore, item: ClipItem) -> some View {
        EditClipSheet(
            item: item,
            contentText: $editingContentText,
            noteText: $editingNoteText,
            onSave: {
                try? store.update(item, content: editingContentText, note: editingNoteText)
                itemPendingEdit = nil
                refreshToken = UUID()
            },
            onCancel: {
                itemPendingEdit = nil
            }
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.black.opacity(0.75))
                .font(.system(size: 14, weight: .medium))

            TextField(
                "",
                text: $searchText,
                prompt: Text("搜索剪贴板历史...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.32))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.84))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func filterBar(store: ClipStore, customTags: [Tag], counts: [UUID: Int]) -> some View {
        HStack(spacing: 0) {
            Button {
                selectedFilter = .all
            } label: {
                Text(ClipFilter.all.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selectedFilter == .all ? Color.white : Color.primary.opacity(0.78))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(selectedFilter == .all ? Color.accentColor : Color.clear)
                    )
            }
            .buttonStyle(.borderless)
            .fixedSize()
            .padding(.leading, 16)
            .padding(.trailing, 8)

            TagReorderScrollStrip(
                tags: customTags,
                counts: counts,
                selectedTagID: selectedTagID,
                isImagesSelected: selectedFilter == .images,
                onSelectImages: {
                    selectedFilter = .images
                },
                onSelectTag: { tagID in
                    selectedFilter = .tag(tagID)
                },
                onMoveTag: { tagID, targetIndex in
                    guard let tag = customTags.first(where: { $0.id == tagID }) else {
                        return
                    }

                    do {
                        try store.moveTag(tag, to: targetIndex)
                        refreshToken = UUID()
                        errorMessage = nil
                    } catch {
                        errorMessage = "标签排序失败：\(error.localizedDescription)"
                        print("Tag reorder failed: \(error.localizedDescription)")
                    }
                },
                onRenameTag: { tagID in
                    guard let tag = customTags.first(where: { $0.id == tagID }) else {
                        return
                    }
                    renameTagName = tag.name
                    tagPendingRename = tag
                },
                onDeleteTag: { tagID in
                    guard let tag = customTags.first(where: { $0.id == tagID }) else {
                        return
                    }
                    tagPendingDelete = tag
                },
                onCreateTag: {
                    isCreateTagSheetPresented = true
                }
            )
            .frame(height: 34)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
            .padding(.top, 1)
            .padding(.bottom, 1)
        }
        .padding(.bottom, 10)
    }

    private var selectedTagID: UUID? {
        guard case .tag(let tagID) = selectedFilter else {
            return nil
        }
        return tagID
    }

    private func composer(store: ClipStore, loadErrorMessage: String?) -> some View {
        let visibleErrorMessage = errorMessage ?? loadErrorMessage

        return VStack(spacing: 10) {
            if let pendingImage {
                PendingImageView(image: pendingImage) {
                    self.pendingImage = nil
                }
                .overlay {
                    if isImageDropTargeted {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            )
                            .overlay(
                                Text("松手即可添加图片")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            )
                    }
                }
            } else {
                SubmitField(
                    placeholder: "在这儿粘贴内容，按下回车发送",
                    text: $composerText,
                    onSubmit: {
                        submit(store: store)
                    },
                    fontSize: 13,
                    focusRequestID: composerContentFocusID
                )
                .frame(minHeight: 22)
            }

            SubmitField(
                placeholder: "添加备注...",
                text: $composerNote,
                onSubmit: {
                    submit(store: store)
                },
                fontSize: 13,
                focusRequestID: composerNoteFocusID
            )
            .frame(minHeight: 24)

            if let visibleErrorMessage, visibleErrorMessage.isEmpty == false {
                Text(visibleErrorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if pendingImage != nil {
                Button("", action: { submit(store: store) })
                    .keyboardShortcut(.defaultAction)
                    .frame(width: 0, height: 0)
                    .opacity(0.001)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 14)
        .background(
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(Color.white)
        )
        .overlay(alignment: .center) {
            if isImageDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .inset(by: 10)
                    .fill(Color.accentColor.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .inset(by: 0.5)
                            .stroke(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    )
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 20, weight: .semibold))
                            Text("将图片放到这里")
                                .font(.system(size: 14, weight: .semibold))
                            Text("松开鼠标后可直接按回车发送")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.secondary)
                        }
                        .foregroundStyle(Color.accentColor)
                    )
                    .allowsHitTesting(false)
            }
        }
        .background(
            ImageDropZone(isTargeted: $isImageDropTargeted) { image in
                pendingImage = image
            }
        )
    }

    private var header: some View {
        HStack {
            Text("Aha paste")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.84))

            Spacer()

            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $isSettingsPresented, arrowEdge: .top) {
                SettingsView()
                    .environmentObject(settings)
                    .environmentObject(appDelegate)
                    .frame(width: 300)
                    .padding(12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var resizeHandle: some View {
        PopoverResizeHandle(
            onResizeChanged: { nextHeight in
                appDelegate.updatePopoverHeight(nextHeight)
            },
            onResizeEnded: {
                appDelegate.persistPopoverHeight()
            },
            currentHeight: {
                appDelegate.currentPopoverHeight
            }
        )
        .frame(height: 8)
    }

    private func showCopyFeedback() {
        toastMessage = "已复制"
        isToastVisible = true

        if settings.isSoundEnabled {
            if let sound = NSSound(named: NSSound.Name(settings.selectedCopySound.title)) {
                sound.volume = 0.22
                sound.play()
            } else {
                NSSound.beep()
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            isToastVisible = false
        }
    }

    private func submit(store: ClipStore) {
        let hasPendingImage = pendingImage != nil
        let trimmedContent = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = composerNote.trimmingCharacters(in: .whitespacesAndNewlines)

        if hasPendingImage == false, trimmedContent.isEmpty, trimmedNote.isEmpty {
            errorMessage = nil
            return
        }

        do {
            errorMessage = nil

            if let pendingImage {
                try store.saveImage(pendingImage, note: composerNote)
            } else {
                try store.saveText(
                    content: composerText,
                    note: composerNote,
                    customTagID: currentComposerCustomTagID
                )
            }

            composerText = ""
            composerNote = ""
            pendingImage = nil
            refreshToken = UUID()
            requestComposerFocus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var currentComposerCustomTagID: UUID? {
        guard case .tag(let id) = selectedFilter else {
            return nil
        }
        return id
    }

    private func requestComposerFocus() {
        if pendingImage != nil {
            composerNoteFocusID += 1
        } else {
            composerContentFocusID += 1
        }
    }

    private func loadData(store: ClipStore) -> LoadedStoreData {
        do {
            let items = try store.fetchItems(searchText: searchText, filter: selectedFilter)
            let customTags = try store.fetchCustomTags()
            let customTagCounts = try store.customTagItemCounts()
            return LoadedStoreData(
                items: items,
                customTags: customTags,
                customTagCounts: customTagCounts,
                errorMessage: nil
            )
        } catch {
            return LoadedStoreData(
                items: [],
                customTags: [],
                customTagCounts: [:],
                errorMessage: error.localizedDescription
            )
        }
    }
}

private struct LoadedStoreData {
    let items: [ClipItem]
    let customTags: [Tag]
    let customTagCounts: [UUID: Int]
    let errorMessage: String?
}

private struct ClipItemDropIndicator: Equatable {
    enum Placement {
        case before
        case after
    }

    let itemID: UUID
    let placement: Placement
    let targetIndex: Int
}

private struct TagChipView: View {
    let title: String
    let countText: String?
    let dotColor: Color?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
            }

            Text(title)

            if let countText {
                Text(countText)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.primary.opacity(0.52))
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.78))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .fixedSize()
    }
}

private struct TagReorderScrollStrip: NSViewRepresentable {
    let tags: [Tag]
    let counts: [UUID: Int]
    let selectedTagID: UUID?
    let isImagesSelected: Bool
    let onSelectImages: () -> Void
    let onSelectTag: (UUID) -> Void
    let onMoveTag: (UUID, Int) -> Void
    let onRenameTag: (UUID) -> Void
    let onDeleteTag: (UUID) -> Void
    let onCreateTag: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> TagReorderStripRootView {
        let view = TagReorderStripRootView()
        view.coordinator = context.coordinator
        view.apply(parent: self)
        return view
    }

    func updateNSView(_ nsView: TagReorderStripRootView, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
        nsView.apply(parent: self)
    }

    final class Coordinator: NSObject {
        var parent: TagReorderScrollStrip

        init(_ parent: TagReorderScrollStrip) {
            self.parent = parent
        }

        @objc func selectImages() {
            parent.onSelectImages()
        }

        @objc func createTag() {
            parent.onCreateTag()
        }

        @objc func renameTag(_ sender: NSMenuItem) {
            guard let tagID = sender.representedObject as? UUID else {
                return
            }
            parent.onRenameTag(tagID)
        }

        @objc func deleteTag(_ sender: NSMenuItem) {
            guard let tagID = sender.representedObject as? UUID else {
                return
            }
            parent.onDeleteTag(tagID)
        }

        func makeMenu(for tagID: UUID) -> NSMenu {
            let menu = NSMenu()

            let renameItem = NSMenuItem(title: "重命名", action: #selector(renameTag(_:)), keyEquivalent: "")
            renameItem.target = self
            renameItem.representedObject = tagID
            menu.addItem(renameItem)

            let deleteItem = NSMenuItem(title: "删除", action: #selector(deleteTag(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = tagID
            menu.addItem(deleteItem)

            return menu
        }
    }
}

private final class HiddenScrollerScrollView: NSScrollView {
    override func tile() {
        super.tile()
        horizontalScroller?.isHidden = true
        horizontalScroller?.alphaValue = 0
        verticalScroller?.isHidden = true
        verticalScroller?.alphaValue = 0
    }
}

private final class TagReorderStripRootView: NSView {
    private let imagesButton = BorderlessHostingButton(rootView: AnyView(EmptyView()))
    private let addButton = NSButton()
    private let scrollView = HiddenScrollerScrollView()
    private let canvasView = TagStripCanvasView()

    weak var coordinator: TagReorderScrollStrip.Coordinator? {
        didSet {
            imagesButton.target = coordinator
            imagesButton.action = #selector(TagReorderScrollStrip.Coordinator.selectImages)
            addButton.target = coordinator
            addButton.action = #selector(TagReorderScrollStrip.Coordinator.createTag)
            canvasView.coordinator = coordinator
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        imagesButton.translatesAutoresizingMaskIntoConstraints = false

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.isBordered = false
        addButton.bezelStyle = .regularSquare
        addButton.imagePosition = .imageOnly
        addButton.contentTintColor = .labelColor
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "添加标签")
        addButton.focusRingType = .none
        addButton.setButtonType(.momentaryPushIn)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = canvasView

        addSubview(imagesButton)
        addSubview(scrollView)
        addSubview(addButton)

        let minScrollWidth = scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 32)
        minScrollWidth.priority = .defaultLow

        NSLayoutConstraint.activate([
            imagesButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            imagesButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: imagesButton.trailingAnchor, constant: 5),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            addButton.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 5),
            addButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 28),
            addButton.heightAnchor.constraint(equalToConstant: 28),

            minScrollWidth
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(parent: TagReorderScrollStrip) {
        imagesButton.update(
            rootView: AnyView(
                TagChipView(
                    title: ClipFilter.images.title,
                    countText: nil,
                    dotColor: nil,
                    isSelected: parent.isImagesSelected
                )
            )
        )
        canvasView.apply(parent: parent)
    }
}

private final class BorderlessHostingButton: NSButton {
    private let hostingView: NSHostingView<AnyView>

    init(rootView: AnyView) {
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        imagePosition = .imageOnly
        translatesAutoresizingMaskIntoConstraints = false

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func update(rootView: AnyView) {
        hostingView.rootView = rootView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class TagStripCanvasView: NSView {
    override var isFlipped: Bool { true }

    weak var coordinator: TagReorderScrollStrip.Coordinator?

    private var tags: [Tag] = []
    private var counts: [UUID: Int] = [:]
    private var selectedTagID: UUID?
    private var chipViews: [UUID: TagChipInteractiveView] = [:]
    private var draggingTagID: UUID?
    private var dragStartFrame: CGRect = .zero
    private var dragTranslationX: CGFloat = 0
    private var targetIndex: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(parent: TagReorderScrollStrip) {
        tags = parent.tags
        counts = parent.counts
        selectedTagID = parent.selectedTagID
        rebuildChipViews()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layoutChips(animated: false)
    }

    private func rebuildChipViews() {
        subviews.forEach { $0.removeFromSuperview() }
        chipViews.removeAll()

        for tag in tags {
            let chipView = TagChipInteractiveView(tagID: tag.id, menu: coordinator?.makeMenu(for: tag.id))
            chipView.update(
                rootView: AnyView(
                    TagChipView(
                        title: tag.name,
                        countText: "\(counts[tag.id, default: 0])",
                        dotColor: tag.accentColor,
                        isSelected: selectedTagID == tag.id
                    )
                )
            )
            chipView.onClick = { [weak self] tagID in
                self?.coordinator?.parent.onSelectTag(tagID)
            }
            chipView.onDragBegan = { [weak self] tagID in
                self?.beginDrag(tagID: tagID)
            }
            chipView.onDragChanged = { [weak self] tagID, translation, locationInWindow in
                self?.updateDrag(tagID: tagID, translation: translation, locationInWindow: locationInWindow)
            }
            chipView.onDragEnded = { [weak self] tagID, translation in
                self?.endDrag(tagID: tagID, translation: translation)
            }
            addSubview(chipView)
            chipViews[tag.id] = chipView
        }
    }

    private func beginDrag(tagID: UUID) {
        guard let chipView = chipViews[tagID] else { return }
        draggingTagID = tagID
        dragStartFrame = chipView.frame
        dragTranslationX = 0
        targetIndex = currentIndex(for: tagID)
        chipView.alphaValue = 0.94
        chipView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        chipView.layer?.shadowOpacity = 1
        chipView.layer?.shadowRadius = 12
        chipView.layer?.shadowOffset = CGSize(width: 0, height: 4)
        chipView.layer?.zPosition = 20
        needsLayout = true
    }

    private func updateDrag(tagID: UUID, translation: CGPoint, locationInWindow: NSPoint) {
        guard draggingTagID == tagID else { return }
        dragTranslationX = clampedTranslationX(for: translation.x)
        autoscrollIfNeeded(locationInWindow: locationInWindow)
        targetIndex = resolvedTargetIndex(for: tagID)
        needsLayout = true
    }

    private func endDrag(tagID: UUID, translation: CGPoint) {
        guard draggingTagID == tagID else { return }
        let sourceIndex = currentIndex(for: tagID) ?? 0
        let resolvedTarget = targetIndex ?? sourceIndex

        if let chipView = chipViews[tagID] {
            chipView.alphaValue = 1
            chipView.layer?.shadowOpacity = 0
            chipView.layer?.zPosition = 0
        }

        draggingTagID = nil
        dragTranslationX = 0
        targetIndex = nil
        needsLayout = true

        if resolvedTarget != sourceIndex {
            coordinator?.parent.onMoveTag(tagID, resolvedTarget)
        }
    }

    private func layoutChips(animated: Bool) {
        let orderedTagIDs = arrangedTagIDs()
        var x: CGFloat = 0
        var widthMap: [UUID: CGFloat] = [:]
        var slotMap: [UUID: CGFloat] = [:]

        for tagID in orderedTagIDs {
            guard let chipView = chipViews[tagID] else { continue }
            let width = chipView.fittingSize.width
            widthMap[tagID] = width
            slotMap[tagID] = x
            x += width + 5
        }

        let contentWidth = max(x - 5, enclosingScrollView?.contentView.bounds.width ?? bounds.width)
        setFrameSize(CGSize(width: contentWidth, height: 34))

        for tag in tags {
            guard let chipView = chipViews[tag.id] else { continue }
            let width = widthMap[tag.id] ?? chipView.fittingSize.width
            let slotX = slotMap[tag.id] ?? 0
            let targetFrame = CGRect(x: slotX, y: 0, width: width, height: 34)

            if draggingTagID == tag.id {
                let dragX = min(max(dragStartFrame.minX + dragTranslationX, 0), max(contentWidth - width, 0))
                chipView.frame = CGRect(x: dragX, y: 0, width: width, height: 34)
            } else if animated {
                chipView.animator().frame = targetFrame
            } else {
                chipView.frame = targetFrame
            }
        }
    }

    private func arrangedTagIDs() -> [UUID] {
        var tagIDs = tags.map(\.id)
        guard
            let draggingTagID,
            let sourceIndex = tagIDs.firstIndex(of: draggingTagID),
            let targetIndex
        else {
            return tagIDs
        }

        let moved = tagIDs.remove(at: sourceIndex)
        tagIDs.insert(moved, at: min(max(targetIndex, 0), tagIDs.count))
        return tagIDs
    }

    private func currentIndex(for tagID: UUID) -> Int? {
        tags.firstIndex(where: { $0.id == tagID })
    }

    private func resolvedTargetIndex(for tagID: UUID) -> Int {
        let draggedMidX = dragStartFrame.midX + dragTranslationX
        let otherIDs = tags.map(\.id).filter { $0 != tagID }

        var index = 0
        for otherID in otherIDs {
            guard let chipView = chipViews[otherID] else { continue }
            if draggedMidX > chipView.frame.midX {
                index += 1
            }
        }
        return index
    }

    private func clampedTranslationX(for translationX: CGFloat) -> CGFloat {
        guard let draggingTagID, let chipView = chipViews[draggingTagID] else {
            return translationX
        }

        let width = chipView.frame.width
        let contentWidth = max(frame.width, enclosingScrollView?.contentView.bounds.width ?? bounds.width)
        let minTranslation = -dragStartFrame.minX
        let maxTranslation = max(contentWidth - dragStartFrame.minX - width, 0)
        return min(max(translationX, minTranslation), maxTranslation)
    }

    private func autoscrollIfNeeded(locationInWindow: NSPoint) {
        guard let scrollView = enclosingScrollView else {
            return
        }

        let locationInScroll = scrollView.convert(locationInWindow, from: nil)
        let visibleWidth = scrollView.contentView.bounds.width
        let maxOffsetX = max(frame.width - visibleWidth, 0)
        guard maxOffsetX > 0 else { return }

        var nextOffsetX = scrollView.contentView.bounds.origin.x
        let edgeInset: CGFloat = 32
        let step: CGFloat = 18

        if locationInScroll.x < edgeInset {
            nextOffsetX = max(nextOffsetX - step, 0)
        } else if locationInScroll.x > visibleWidth - edgeInset {
            nextOffsetX = min(nextOffsetX + step, maxOffsetX)
        }

        guard nextOffsetX != scrollView.contentView.bounds.origin.x else { return }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: nextOffsetX, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

private final class TagChipInteractiveView: NSView {
    override var isFlipped: Bool { true }

    let tagID: UUID
    var onClick: ((UUID) -> Void)?
    var onDragBegan: ((UUID) -> Void)?
    var onDragChanged: ((UUID, CGPoint, NSPoint) -> Void)?
    var onDragEnded: ((UUID, CGPoint) -> Void)?

    private let hostingView: NSHostingView<AnyView>

    init(tagID: UUID, menu: NSMenu?) {
        self.tagID = tagID
        self.hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: .zero)
        self.menu = menu
        wantsLayer = true
        layer?.masksToBounds = false

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(rootView: AnyView) {
        hostingView.rootView = rootView
    }

    override func mouseDown(with event: NSEvent) {
        let startPoint = event.locationInWindow
        var lastPoint = startPoint
        var hasDragged = false

        while let nextEvent = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            lastPoint = nextEvent.locationInWindow
            switch nextEvent.type {
            case .leftMouseDragged:
                let translation = CGPoint(x: lastPoint.x - startPoint.x, y: lastPoint.y - startPoint.y)
                if hasDragged == false, abs(translation.x) > 3 {
                    hasDragged = true
                    onDragBegan?(tagID)
                }
                if hasDragged {
                    onDragChanged?(tagID, translation, lastPoint)
                }
            case .leftMouseUp:
                let translation = CGPoint(x: lastPoint.x - startPoint.x, y: lastPoint.y - startPoint.y)
                if hasDragged {
                    onDragEnded?(tagID, translation)
                } else {
                    onClick?(tagID)
                }
                return
            default:
                break
            }
        }
    }
}

private struct EditClipSheet: View {
    let item: ClipItem
    @Binding var contentText: String
    @Binding var noteText: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let editorFill = Color(NSColor.controlBackgroundColor)
        let groupedFill = Color(NSColor.windowBackgroundColor)

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("编辑卡片")
                    .font(.system(size: 18, weight: .semibold))

                Text(item.kind == .text ? "修改内容和备注" : "修改图片备注")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if item.kind == .text {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("内容")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextEditor(text: $contentText)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .frame(height: 84)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(editorFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                    )
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("备注")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $noteText)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(height: 40)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(editorFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 18)
            .background(groupedFill)

            Divider()

            HStack(spacing: 10) {
                Spacer()

                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 350)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct PopoverResizeHandle: NSViewRepresentable {
    let onResizeChanged: (CGFloat) -> Void
    let onResizeEnded: () -> Void
    let currentHeight: () -> CGFloat

    func makeNSView(context: Context) -> ResizeTrackingView {
        let view = ResizeTrackingView()
        view.onResizeChanged = onResizeChanged
        view.onResizeEnded = onResizeEnded
        view.currentHeight = currentHeight
        return view
    }

    func updateNSView(_ nsView: ResizeTrackingView, context: Context) {
        nsView.onResizeChanged = onResizeChanged
        nsView.onResizeEnded = onResizeEnded
        nsView.currentHeight = currentHeight
    }
}

private final class ResizeTrackingView: NSView {
    var onResizeChanged: ((CGFloat) -> Void)?
    var onResizeEnded: (() -> Void)?
    var currentHeight: (() -> CGFloat)?

    private var initialMouseScreenY: CGFloat?
    private var initialHeight: CGFloat?
    private var cursorPushed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        initialMouseScreenY = NSEvent.mouseLocation.y
        initialHeight = currentHeight?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initialMouseScreenY, let initialHeight else {
            return
        }

        let deltaY = NSEvent.mouseLocation.y - initialMouseScreenY
        onResizeChanged?(initialHeight - deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        initialMouseScreenY = nil
        initialHeight = nil
        onResizeEnded?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    override func mouseEntered(with event: NSEvent) {
        if cursorPushed == false {
            NSCursor.resizeUpDown.push()
            cursorPushed = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }
}

private extension ClipFilter {
    var title: String {
        switch self {
        case .all:
            return SystemTagName.all
        case .images:
            return SystemTagName.images
        case .tag:
            return ""
        }
    }
}

private struct CreateTagSheet: View {
    let title: String
    let fieldPlaceholder: String
    @Binding var newTagName: String
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))

                Text("输入分类名称")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 8) {
                TextField(fieldPlaceholder, text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
            }
            .padding(20)

            HStack(spacing: 10) {
                Spacer()

                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(title == "重命名分类" ? "保存" : "创建", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 360)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
