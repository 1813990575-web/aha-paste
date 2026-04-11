import AppKit
import SwiftUI

struct ClipRowView: View {
    let item: ClipItem
    let availableTags: [Tag]
    let currentTag: Tag?
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onTagChange: (Tag?) -> Void
    private let cardCornerRadius: CGFloat = 13
    @State private var isTagPickerPresented = false

    private var tagBorderColor: Color {
        currentTag?.accentColor.opacity(0.32) ?? Color.black.opacity(0.08)
    }

    private var tagBackgroundColor: Color {
        currentTag?.accentColor.opacity(0.12) ?? Color.black.opacity(0.05)
    }

    private var tagForegroundColor: Color {
        currentTag?.accentColor.opacity(0.95) ?? Color.secondary.opacity(0.95)
    }

    private var displayTitle: String {
        return item.contentText ?? ""
    }

    private var displayBody: String? {
        guard item.note.isEmpty == false else {
            return nil
        }
        return item.note
    }

    private var contentURL: URL? {
        guard let raw = item.contentText?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return nil
        }

        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else {
            return nil
        }

        guard scheme == "http" || scheme == "https" else {
            return nil
        }

        return url
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if item.kind == .text {
                        Button {
                            isTagPickerPresented.toggle()
                        } label: {
                            HStack(spacing: 5) {
                                Text(currentTag?.name ?? "无分类")

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tagForegroundColor)
                            .padding(.leading, 10)
                            .padding(.trailing, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(tagBackgroundColor)
                                    .overlay(
                                        Capsule()
                                            .stroke(tagBorderColor, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .popover(isPresented: $isTagPickerPresented, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 4) {
                                Button {
                                    onTagChange(nil)
                                    isTagPickerPresented = false
                                } label: {
                                    tagPickerRow(title: "无分类", color: nil)
                                }
                                .buttonStyle(.plain)

                                ForEach(availableTags, id: \.id) { tag in
                                    Button {
                                        onTagChange(tag)
                                        isTagPickerPresented = false
                                    } label: {
                                        tagPickerRow(title: tag.name, color: tag.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(8)
                            .frame(width: 160, alignment: .leading)
                        }
                    } else {
                        Text("图片")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(item.createdAt.formatted(date: .numeric, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                if item.kind == .image,
                   let relativePath = item.imageRelativePath,
                   let image = try? ImageFileStore.shared.load(relativePath: relativePath) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 116)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        )
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        if item.note.isEmpty, let contentURL, let raw = item.contentText {
                            Link(destination: contentURL) {
                                Text(raw)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .underline(false)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .modifier(LinkCursorModifier())
                        } else {
                            Text(displayTitle)
                                .font(.system(size: 12.5, weight: .semibold))
                                .lineSpacing(2)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let displayBody {
                            Text(displayBody)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.leading, 10)
                }
            }
            .padding(14)
            .padding(.trailing, 26)
            .background(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .onTapGesture(perform: onCopy)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
        .contextMenu {
            Button("编辑", action: onEdit)
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private func tagPickerRow(title: String, color: Color?) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color ?? Color.clear)
                .frame(width: 6, height: 6)
                .overlay {
                    if color == nil {
                        Circle()
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    }
                }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }
}

private struct LinkCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            CursorTrackingOverlay(cursor: .pointingHand)
                .allowsHitTesting(false)
        }
    }
}

private struct CursorTrackingOverlay: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorTrackingView {
        let view = CursorTrackingView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: CursorTrackingView, context: Context) {
        nsView.cursor = cursor
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

private final class CursorTrackingView: NSView {
    var cursor: NSCursor = .arrow

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var isFlipped: Bool {
        true
    }
}
