import AppKit
import SwiftUI
import GamepadKeymapperCore

struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Text(model.statusLine)
        Toggle("Mapping Enabled", isOn: Binding(
            get: { model.settings.mappingEnabled },
            set: { model.setMappingEnabled($0) }
        ))
        if let name = model.frontmostName {
            Text("Frontmost: \(name)")
        }
        if !model.accessibilityTrusted {
            Button("Grant Accessibility…") {
                model.openAccessibilitySettings()
            }
        }
        Divider()
        Button("Open Editor…") {
            model.showEditor()
        }
        if model.settings.profileOverrideID != nil {
            Button("Use Automatic Profile") {
                model.clearOverride()
            }
        }
        Menu("Pin Profile") {
            ForEach(model.document.profiles) { profile in
                Button(pinTitle(profile)) {
                    model.pin(profileID: profile.id)
                }
            }
        }
        Divider()
        Button("Quit Gamepad Keymapper") {
            NSApp.terminate(nil)
        }
    }

    private func pinTitle(_ profile: Profile) -> String {
        model.settings.profileOverrideID == profile.id ? "✓ \(profile.name)" : profile.name
    }
}
