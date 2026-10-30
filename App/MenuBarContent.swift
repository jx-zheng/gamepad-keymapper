import AppKit
import SwiftUI

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
        if model.settings.profileOverrideID != nil {
            Text("Pinned — ignores frontmost app")
            Button("Automatic") {
                model.clearOverride()
            }
        } else {
            Text("Automatic")
        }
        if !model.accessibilityTrusted {
            Text(model.controllers.isEmpty
                 ? "Accessibility is off. Keys and mouse from a controller will not be sent."
                 : "Controller connected. Accessibility is off, so keys and clicks are blocked.")
            if let last = model.lastInputName {
                Text("Last press: \(last)")
            }
            Button("Open Accessibility Settings") {
                model.openAccessibilitySettings()
                model.showEditor()
            }
        }
        Divider()
        Button("Open Editor…") {
            model.showEditor()
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
