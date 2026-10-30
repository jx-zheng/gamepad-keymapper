import AppKit
import Foundation
import SwiftUI

final class RadialModel: ObservableObject {
    @Published var menu: RadialMenu?
    @Published var selection: Int?
}

/// One non-activating panel. Selection changes only when the highlighted slice changes,
/// so stick noise does not redraw every sample. Call from the main thread.
final class RadialOverlay {
    private let model = RadialModel()
    private var panel: NSPanel?

    func show(menu: RadialMenu, selection: Int?) {
        model.menu = menu
        model.selection = selection
        let panel = ensurePanel()
        place(panel)
        panel.orderFrontRegardless()
    }

    func update(selection: Int?) {
        guard model.selection != selection else { return }
        model.selection = selection
    }

    func hide() {
        model.menu = nil
        model.selection = nil
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let host = NSHostingController(rootView: RadialMenuView(model: model))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = host
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        self.panel = panel
        return panel
    }

    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 520, height: 520)
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        ))
    }
}

struct RadialMenuView: View {
    @ObservedObject var model: RadialModel

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 390, height: 390)
                .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
            if let menu = model.menu {
                let count = max(menu.items.count, 1)
                ForEach(Array(menu.items.enumerated()), id: \.element.id) { index, item in
                    let center = RadialGeometry.sliceCenter(index: index, count: count)
                    let selected = model.selection == index
                    Text(item.label)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected ? Color.accentColor.opacity(0.9) : Color.black.opacity(0.08), in: Capsule())
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .offset(x: center.x * 132, y: -center.y * 132)
                }
            }
            VStack(spacing: 2) {
                Text(centerTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(centerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 110)
            .multilineTextAlignment(.center)
        }
        .frame(width: 520, height: 520)
    }

    private var centerTitle: String {
        guard let menu = model.menu else { return "" }
        if let selection = model.selection, menu.items.indices.contains(selection) {
            return menu.items[selection].label
        }
        return menu.name
    }

    private var centerSubtitle: String {
        model.selection == nil ? "Aim, then release" : "Release to run"
    }
}
