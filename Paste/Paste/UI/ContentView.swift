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
    @State private var draggedTagID: UUID?

    var body: some View {
        let store = ClipStore(context: modelContext)
        let items = (try? store.fetchItems(searchText: searchText, filter: selectedFilter)) ?? []
        let customTags = (try? store.fetchCustomTags()) ?? []
        let customTagCounts = (try? store.customTagItemCounts()) ?? [:]

        VStack(spacing: 0) {
            header
            searchBar
            filterBar(store: store, customTags: customTags, counts: customTagCounts)
            Divider()
            itemsList(store: store, items: items, customTags: customTags)
            Divider()
            composer(store: store)
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
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(items, id: \.id) { item in
                    clipRow(store: store, item: item, customTags: customTags)
                }
            }
            .padding(16)
        }
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    Button {
                        selectedFilter = .images
                    } label: {
                        Text(ClipFilter.images.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedFilter == .images ? Color.white : Color.primary.opacity(0.78))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(selectedFilter == .images ? Color.accentColor : Color.clear)
                            )
                    }
                    .buttonStyle(.borderless)
                    .fixedSize()

                    ForEach(customTags, id: \.id) { tag in
                        tagFilterButton(
                            store: store,
                            tag: tag,
                            customTags: customTags,
                            count: counts[tag.id, default: 0]
                        )
                    }

                    Button {
                        isCreateTagSheetPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .fixedSize()
                }
                .padding(.trailing, 8)
            }
        }
        .padding(.bottom, 10)
    }

    private func tagFilterButton(store: ClipStore, tag: Tag, customTags: [Tag], count: Int) -> some View {
        let isSelected = selectedFilter == .tag(tag.id)

        return Button {
            selectedFilter = .tag(tag.id)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(tag.accentColor)
                    .frame(width: 6, height: 6)

                Text(tag.name)

                Text("\(count)")
                    .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.primary.opacity(0.52))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.78))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .opacity(draggedTagID == tag.id ? 0.72 : 1)
        .onDrag {
            draggedTagID = tag.id
            return NSItemProvider(object: tag.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: TagReorderDropDelegate(
                targetTag: tag,
                tags: customTags,
                draggedTagID: $draggedTagID,
                onMove: { draggedTag, targetIndex in
                    try? store.moveTag(draggedTag, to: targetIndex)
                    refreshToken = UUID()
                }
            )
        )
        .contextMenu {
            Button("重命名") {
                renameTagName = tag.name
                tagPendingRename = tag
            }
            Button("删除", role: .destructive) {
                tagPendingDelete = tag
            }
        }
    }

    private func composer(store: ClipStore) -> some View {
        VStack(spacing: 10) {
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

            if let errorMessage, errorMessage.isEmpty == false {
                Text(errorMessage)
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
}

private struct TagReorderDropDelegate: DropDelegate {
    let targetTag: Tag
    let tags: [Tag]
    @Binding var draggedTagID: UUID?
    let onMove: (Tag, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard
            let draggedTagID,
            draggedTagID != targetTag.id,
            let draggedTag = tags.first(where: { $0.id == draggedTagID }),
            let targetIndex = tags.firstIndex(where: { $0.id == targetTag.id })
        else {
            return
        }

        onMove(draggedTag, targetIndex)
    }

    func validateDrop(info: DropInfo) -> Bool {
        true
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTagID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        guard info.location.x.isNaN == false else {
            return
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
