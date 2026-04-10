import AppKit
import SwiftUI

struct PendingImageView: View {
    let image: NSImage
    let onClear: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )

            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .font(.system(size: 20))
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
    }
}
