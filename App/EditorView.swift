import SwiftUI

enum EditorMetrics {
    static let sidebarWidth: CGFloat = 232
    static let minimumWidth: CGFloat = 900
    static let minimumHeight: CGFloat = 600
    static let defaultWidth: CGFloat = 1120
    static let defaultHeight: CGFloat = 740
    /// Detail width where the control list and the action editor sit side by side.
    static let bindingsSideBySide: CGFloat = 760
}

struct EditorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        editor
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if !model.accessibilityTrusted {
                        accessibilityBanner
                    }
                    if model.savesDisabled {
                        unsavedBanner
                    }
                }
            }
    }

    private var accessibilityBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("Accessibility is off, so keys and clicks are not sent. Turn on Gamepad Keymapper in Privacy & Security → Accessibility, then quit and reopen the app. The radial menu can still open.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let last = model.lastInputName {
                    Text("Last press: \(last) — received from the controller, not sent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button("Open System Settings") { model.openAccessibilitySettings() }
                .help("After you turn it on, quit and reopen Gamepad Keymapper.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .center)
        .background {
            // Flatten the tint onto an opaque fill so the sidebar divider cannot show through.
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Color.yellow.opacity(0.28)
            }
            .compositingGroup()
        }
    }

    private var unsavedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Profiles and settings are not being saved. The file on disk was left unchanged. Import a profile or restore the sample to start saving again.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Restore Sample") { model.resetToSample() }
        }
        .padding(12)
        .background(Color.orange.opacity(0.15))
    }

    private var editor: some View {
        NavigationStack {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: EditorMetrics.sidebarWidth)
                    .frame(maxHeight: .infinity)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar {
                ToolbarItemGroup {
                    Button("Import") { model.importProfiles() }
                    Button("Export") { model.exportProfiles() }
                }
            }
        }
        .frame(minWidth: EditorMetrics.minimumWidth, minHeight: EditorMetrics.minimumHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.sidebar) { _, item in
            if model.captureBindingID != nil {
                model.disarmCapture()
            }
            model.engine.setDevicesVisible(item == .devices)
        }
        .alert("Gamepad Keymapper", isPresented: alertShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var alertShown: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.sidebar) {
                Section("Profiles") {
                    ForEach(model.document.profiles) { profile in
                        HStack(spacing: 8) {
                            Text(profile.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            Spacer(minLength: 4)
                            if profile.id == model.activeProfileID {
                                Image(systemName: "dot.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .help("Receiving controller input")
                            }
                        }
                        .tag(SidebarItem.profile(profile.id))
                    }
                }
                Section {
                    Button("Add Profile", action: model.addProfile)
                        .disabled(model.document.profiles.count >= ProfileSanitizer.maxProfiles)
                }
            }
            .listStyle(.sidebar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            sidebarFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Same sidebar list style as Profiles, anchored to the bottom of the column.
    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 10)
            List(selection: $model.sidebar) {
                Label("Devices", systemImage: "gamecontroller")
                    .tag(SidebarItem.devices)
                Label("Permissions", systemImage: "lock.shield")
                    .tag(SidebarItem.permissions)
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .frame(height: 84)
        }
        .padding(.bottom, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            switch model.sidebar {
            case .profile(let id):
                if model.document.profiles.contains(where: { $0.id == id }) {
                    ProfileEditor(profileID: id)
                } else {
                    ContentUnavailableView("No Profile", systemImage: "rectangle.dashed", description: Text("Add a profile to start mapping."))
                }
            case .devices:
                DevicesView()
            case .permissions:
                PermissionsView()
            }
        }
    }

}

private struct ProfileEditor: View {
    @EnvironmentObject private var model: AppModel
    let profileID: UUID

    private var profile: Profile? {
        model.document.profiles.first { $0.id == profileID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let profile {
                profileHeader(profile)
                Picker("Section", selection: $model.editorTab) {
                    ForEach(EditorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                Divider()
                switch model.editorTab {
                case .bindings:
                    BindingsTab(profile: profile)
                case .pointer:
                    PointerTab(profile: profile)
                case .radial:
                    RadialTab(profile: profile)
                case .apps:
                    AppsTab(profile: profile)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func profileHeader(_ profile: Profile) -> some View {
        ViewThatFits(in: .horizontal) {
            profileHeaderRow(profile, stacksControls: false)
            profileHeaderRow(profile, stacksControls: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func profileHeaderRow(_ profile: Profile, stacksControls: Bool) -> some View {
        let title = VStack(alignment: .leading, spacing: 2) {
            TextField("Profile name", text: Binding(
                get: { profile.name },
                set: { name in model.update(profile.id) { $0.name = name } }
            ))
            .font(.title2)
            .textFieldStyle(.plain)
            Text(profileModeCaption(profile))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        let controls = HStack(spacing: 10) {
            Toggle("Enabled", isOn: Binding(
                get: { profile.enabled },
                set: { enabled in model.update(profile.id) { $0.enabled = enabled } }
            ))
            Toggle("Default", isOn: Binding(
                get: { profile.isDefault },
                set: { isDefault in if isDefault { model.makeDefault(profile.id) } }
            ))
            if model.settings.profileOverrideID == profile.id {
                Button("Automatic") { model.clearOverride() }
            } else {
                Button("Pin") { model.pin(profileID: profile.id) }
            }
            Button("Duplicate") { model.duplicate(profileID: profile.id) }
                .disabled(model.document.profiles.count >= ProfileSanitizer.maxProfiles)
            Button("Delete", role: .destructive) { model.delete(profileID: profile.id) }
                .disabled(model.document.profiles.count < 2)
        }

        return Group {
            if stacksControls {
                VStack(alignment: .leading, spacing: 8) {
                    title
                    controls
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    title
                    controls
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private func profileModeCaption(_ profile: Profile) -> String {
        if model.settings.profileOverrideID == profile.id {
            return "Pinned — ignores frontmost app"
        }
        if model.settings.profileOverrideID != nil {
            return "Automatic is off — another profile is pinned"
        }
        return "Automatic"
    }
}

private struct BindingsTab: View {
    @EnvironmentObject private var model: AppModel
    let profile: Profile
    @State private var selectedButtonID: String?
    @State private var unmappedDraft = MapperAction.keyboard(.tap("space"))

    private var layer: Layer? {
        if let id = model.editingLayerID, let match = profile.layers.first(where: { $0.id == id }) {
            return match
        }
        return profile.layers.first
    }

    var body: some View {
        GeometryReader { geo in
            let sideBySide = geo.size.width >= EditorMetrics.bindingsSideBySide
            if sideBySide {
                HStack(spacing: 0) {
                    controlColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    inspectorColumn
                        .frame(width: min(400, max(280, geo.size.width * 0.38)))
                        .frame(maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    controlColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    inspectorColumn
                        .frame(maxWidth: .infinity)
                        .frame(height: max(220, geo.size.height * 0.42))
                }
            }
        }
        .onAppear {
            model.editingLayerID = layer?.id ?? profile.layers.first?.id
            if selectedButtonID == nil {
                selectedButtonID = layer?.bindings.first?.button.id ?? ControllerButton.a.id
            }
        }
        .onChange(of: selectedButtonID) { _, _ in
            unmappedDraft = .keyboard(.tap("space"))
        }
    }

    private var controlColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let layer {
                Picker("Layer", selection: layerSelection) {
                    ForEach(profile.layers) { item in
                        Text(layerTitle(item)).tag(Optional(item.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Hold or toggle a button to switch layers. Base is always on when no other layer is active. The button that shows a layer does not also run a Base action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Add Layer") { model.addLayer(to: profile.id) }
                        .disabled(profile.layers.count >= ProfileSanitizer.maxLayers)
                    Button("Delete Layer") {
                        if let id = layer.id as UUID? {
                            model.deleteLayer(profileID: profile.id, layerID: id)
                        }
                    }
                    .disabled(profile.layers.count < 2 || isBase(layer))
                    Spacer(minLength: 8)
                    Button("Add Binding") {
                        model.editingLayerID = layer.id
                        selectedButtonID = ControllerButton.a.id
                        model.addBinding(profileID: profile.id, layerID: layer.id)
                    }
                    .disabled(layer.bindings.count >= ProfileSanitizer.maxBindings)
                }
                layerActivation(layer)
                List(selection: $selectedButtonID) {
                    ForEach(ControlSection.editor) { section in
                        Section(section.title) {
                            ForEach(section.buttons, id: \.id) { button in
                                controlRow(button, in: layer)
                            }
                        }
                    }
                    if !extraButtons(in: layer).isEmpty {
                        Section("Other") {
                            ForEach(extraButtons(in: layer), id: \.id) { button in
                                controlRow(button, in: layer)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !profile.validationWarnings().isEmpty {
                    ForEach(profile.validationWarnings(), id: \.self) { warning in
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var inspectorColumn: some View {
        Group {
            if let layer, let button = selectedControl(in: layer) {
                inspector(layer: layer, button: button)
            } else {
                ContentUnavailableView("Select a Control", systemImage: "gamecontroller", description: Text("Choose a button, stick, or trigger to edit its action."))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func binding(for button: ControllerButton, in layer: Layer) -> ButtonBinding? {
        layer.bindings.first { $0.button.id == button.id }
    }

    private func extraButtons(in layer: Layer) -> [ControllerButton] {
        let known = Set(ControlSection.editor.flatMap { $0.buttons.map(\.id) })
        var seen = Set<String>()
        return layer.bindings.compactMap { binding in
            guard !known.contains(binding.button.id), seen.insert(binding.button.id).inserted else { return nil }
            return binding.button
        }
    }

    private func selectedControl(in layer: Layer) -> ControllerButton? {
        guard let selectedButtonID else { return nil }
        if let known = ControlSection.editor.flatMap(\.buttons).first(where: { $0.id == selectedButtonID }) {
            return known
        }
        return extraButtons(in: layer).first { $0.id == selectedButtonID }
    }

    private func controlRow(_ button: ControllerButton, in layer: Layer) -> some View {
        let binding = binding(for: button, in: layer)
        let summary = binding?.action.summary ?? "Not Mapped"
        let listening = layer.bindings.contains { $0.button.id == button.id && $0.id == model.captureBindingID }
        return HStack(spacing: 8) {
            ControlGlyph(button: button)
            Text(button.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if listening {
                Text("Press a button…")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            } else {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(binding == nil ? Color.secondary.opacity(0.7) : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 2)
        .tag(Optional(button.id))
        .contextMenu {
            if let binding {
                Button("Delete") {
                    model.deleteBinding(profileID: profile.id, layerID: layer.id, bindingID: binding.id)
                }
            }
        }
    }

    private var layerSelection: Binding<UUID?> {
        Binding(
            get: { layer?.id },
            set: { newID in
                if newID != model.editingLayerID, model.captureBindingID != nil {
                    model.disarmCapture()
                }
                model.editingLayerID = newID
            }
        )
    }

    private func inspector(layer: Layer, button: ControllerButton) -> some View {
        let binding = binding(for: button, in: layer)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ControlGlyph(button: button)
                    Text(button.displayName)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let binding {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            buttonPicker(binding, layer: layer)
                            captureButton(binding, layer: layer)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            buttonPicker(binding, layer: layer)
                            captureButton(binding, layer: layer)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ActionEditor(
                        action: binding.action,
                        shortcutNames: model.shortcutNames,
                        onChange: { action in
                            model.setAction(profileID: profile.id, layerID: layer.id, bindingID: binding.id, action: action)
                        },
                        onTest: { model.test(action: binding.action) },
                        onRefreshShortcuts: { model.refreshShortcuts() }
                    )
                    Button("Delete Binding", role: .destructive) {
                        model.deleteBinding(profileID: profile.id, layerID: layer.id, bindingID: binding.id)
                    }
                } else {
                    Text("Not mapped. Choose an action to add it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ActionEditor(
                        action: unmappedDraft,
                        shortcutNames: model.shortcutNames,
                        onChange: { action in
                            unmappedDraft = action
                            model.setActionForButton(profileID: profile.id, layerID: layer.id, button: button, action: action)
                        },
                        onTest: { model.test(action: unmappedDraft) },
                        onRefreshShortcuts: { model.refreshShortcuts() }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func buttonPicker(_ binding: ButtonBinding, layer: Layer) -> some View {
        Picker("Button", selection: Binding(
            get: { binding.button.id },
            set: { id in
                if id != binding.button.id, model.captureBindingID == binding.id {
                    model.disarmCapture()
                }
                model.update(profile.id) { profile in
                    guard let layerIndex = profile.layers.firstIndex(where: { $0.id == layer.id }),
                          let bindingIndex = profile.layers[layerIndex].bindings.firstIndex(where: { $0.id == binding.id }) else { return }
                    profile.layers[layerIndex].bindings[bindingIndex].button = ControllerButton(id: id)
                }
                selectedButtonID = id
            }
        )) {
            ForEach(ControllerButton.catalog, id: \.id) { item in
                Text(item.displayName).tag(item.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func captureButton(_ binding: ButtonBinding, layer: Layer) -> some View {
        Button(model.captureBindingID == binding.id ? "Listening…" : "Capture") {
            model.editingLayerID = layer.id
            model.beginCapture(bindingID: binding.id)
        }
    }

    private func layerActivation(_ layer: Layer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .base = layer.activation {
                Text("These bindings are always on, until a layer below replaces them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        layerModePicker(layer)
                        layerButtonPicker(layer)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        layerModePicker(layer)
                        layerButtonPicker(layer)
                    }
                }
                if layer.activation.activator != nil {
                    Toggle("Unmapped buttons still use Base", isOn: Binding(
                        get: { layer.allowsFallthrough },
                        set: { value in
                            model.update(profile.id) { profile in
                                guard let index = profile.layers.firstIndex(where: { $0.id == layer.id }) else { return }
                                profile.layers[index].allowsFallthrough = value
                            }
                        }
                    ))
                    .help("When this is off, a button you did not map on this layer does nothing while the layer is showing.")
                }
            }
        }
    }

    private func layerModePicker(_ layer: Layer) -> some View {
        Picker("Show this layer", selection: activationKind(layer)) {
            Text("While holding").tag("hold")
            Text("Toggled").tag("toggle")
        }
        .frame(minWidth: 140, idealWidth: 180)
    }

    private func layerButtonPicker(_ layer: Layer) -> some View {
        Picker("On button", selection: activatorBinding(layer)) {
            ForEach(ControllerButton.catalog, id: \.id) { button in
                Text(button.displayName).tag(button.id)
            }
        }
        .help("This button only shows the layer. It does not also run a Base binding.")
    }

    private func activationKind(_ layer: Layer) -> Binding<String> {
        Binding(
            get: {
                if case .toggle = layer.activation { return "toggle" }
                return "hold"
            },
            set: { kind in
                model.update(profile.id) { profile in
                    guard let index = profile.layers.firstIndex(where: { $0.id == layer.id }),
                          let button = profile.layers[index].activation.activator else { return }
                    profile.layers[index].activation = kind == "toggle" ? .toggle(button) : .hold(button)
                }
            }
        )
    }

    private func activatorBinding(_ layer: Layer) -> Binding<String> {
        Binding(
            get: { layer.activation.activator?.id ?? ControllerButton.leftShoulder.id },
            set: { id in
                let button = ControllerButton(id: id)
                model.update(profile.id) { profile in
                    guard let index = profile.layers.firstIndex(where: { $0.id == layer.id }) else { return }
                    if case .toggle = profile.layers[index].activation {
                        profile.layers[index].activation = .toggle(button)
                    } else {
                        profile.layers[index].activation = .hold(button)
                    }
                }
            }
        )
    }

    private func layerTitle(_ layer: Layer) -> String {
        switch layer.activation {
        case .base:
            return "\(layer.name) (always on)"
        case .hold(let button):
            return "\(layer.name) (while holding \(button.displayName))"
        case .toggle(let button):
            return "\(layer.name) (toggled with \(button.displayName))"
        }
    }

    private func isBase(_ layer: Layer) -> Bool {
        if case .base = layer.activation { return true }
        return false
    }
}

private struct PointerTab: View {
    @EnvironmentObject private var model: AppModel
    let profile: Profile

    var body: some View {
        Form {
            Section("Left stick") {
                stickControls(side: .left, mode: profile.sticks.left)
            }
            Section("Right stick") {
                stickControls(side: .right, mode: profile.sticks.right)
            }
            Section("Motion pointer") {
                Toggle("Use gyro when the controller reports motion", isOn: Binding(
                    get: { profile.gyro.enabled },
                    set: { enabled in model.update(profile.id) { $0.gyro.enabled = enabled } }
                ))
                Text("Yaw moves horizontally and pitch moves vertically. Turn on invert if a DualSense, Pro Controller, or Joy-Con drifts the wrong way. Motion is read only while this is enabled and its activation matches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                slider("Speed", value: profile.gyro.sensitivity, range: 100...3000) { value in
                    model.update(profile.id) { $0.gyro.sensitivity = value }
                }
                slider("Deadzone", value: profile.gyro.deadzone, range: 0...0.6) { value in
                    model.update(profile.id) { $0.gyro.deadzone = value }
                }
                Toggle("Invert X", isOn: Binding(
                    get: { profile.gyro.invertX },
                    set: { value in model.update(profile.id) { $0.gyro.invertX = value } }
                ))
                Toggle("Invert Y", isOn: Binding(
                    get: { profile.gyro.invertY },
                    set: { value in model.update(profile.id) { $0.gyro.invertY = value } }
                ))
                Picker("Active", selection: gyroMode) {
                    Text("Always").tag("always")
                    Text("While a button is held").tag("whileHeld")
                }
                if case .whileHeld(let button) = profile.gyro.activation {
                    Picker("Button", selection: Binding(
                        get: { button.id },
                        set: { id in model.update(profile.id) { $0.gyro.activation = .whileHeld(ControllerButton(id: id)) } }
                    )) {
                        ForEach(ControllerButton.catalog, id: \.id) { item in
                            Text(item.displayName).tag(item.id)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var gyroMode: Binding<String> {
        Binding(
            get: {
                if case .always = profile.gyro.activation { return "always" }
                return "whileHeld"
            },
            set: { mode in
                model.update(profile.id) { profile in
                    if mode == "always" {
                        profile.gyro.activation = .always
                    } else if case .whileHeld = profile.gyro.activation {
                        return
                    } else {
                        profile.gyro.activation = .whileHeld(.leftTrigger)
                    }
                }
            }
        )
    }

    private func stickControls(side: StickSide, mode: StickMode) -> some View {
        let choice = StickChoice(mode)
        return VStack(alignment: .leading) {
            Picker("Mode", selection: Binding(
                get: { choice },
                set: { newChoice in
                    model.update(profile.id) { profile in
                        let updated = newChoice.mode(preserving: mode)
                        if side == .left { profile.sticks.left = updated } else { profile.sticks.right = updated }
                    }
                }
            )) {
                ForEach(StickChoice.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            if case .mouse(let sensitivity) = mode {
                slider("Pointer speed", value: sensitivity, range: 200...3000) { value in
                    model.update(profile.id) { profile in
                        if side == .left { profile.sticks.left = .mouse(sensitivity: value) }
                        else { profile.sticks.right = .mouse(sensitivity: value) }
                    }
                }
                Text("Pixels per second at full tilt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if case .scroll(let sensitivity) = mode {
                slider("Scroll speed", value: sensitivity, range: 40...1200) { value in
                    model.update(profile.id) { profile in
                        if side == .left { profile.sticks.left = .scroll(sensitivity: value) }
                        else { profile.sticks.right = .scroll(sensitivity: value) }
                    }
                }
                Text("Scroll pixels per second at full tilt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if case .digital = mode {
                Text("Cardinal directions become buttons such as Left Stick Up. Bind them on the Bindings tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func slider(_ title: String, value: Double, range: ClosedRange<Double>, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .frame(minWidth: 72, idealWidth: 120, alignment: .leading)
                .layoutPriority(1)
            Slider(value: Binding(get: { value }, set: set), in: range)
            Text(value, format: .number.precision(.fractionLength(0...2)))
                .frame(minWidth: 36, idealWidth: 56, alignment: .trailing)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
        }
    }
}

private enum StickChoice: String, CaseIterable, Identifiable {
    case directions = "Directions"
    case pointer = "Pointer"
    case scroll = "Scroll"
    var id: String { rawValue }

    init(_ mode: StickMode) {
        switch mode {
        case .digital: self = .directions
        case .mouse: self = .pointer
        case .scroll: self = .scroll
        }
    }

    func mode(preserving existing: StickMode) -> StickMode {
        switch self {
        case .directions:
            return .digital
        case .pointer:
            let speed: Double
            if case .mouse(let sensitivity) = existing { speed = sensitivity } else { speed = 1080 }
            return .mouse(sensitivity: speed)
        case .scroll:
            let speed: Double
            if case .scroll(let sensitivity) = existing { speed = sensitivity } else { speed = 360 }
            return .scroll(sensitivity: speed)
        }
    }
}

private struct RadialTab: View {
    @EnvironmentObject private var model: AppModel
    let profile: Profile
    @State private var selectedMenu: UUID?
    @State private var expandedSlice: UUID?

    private var menu: RadialMenu? {
        if let selectedMenu, let match = profile.radialMenus.first(where: { $0.id == selectedMenu }) {
            return match
        }
        return profile.radialMenus.first
    }

    var body: some View {
        Group {
            if profile.radialMenus.isEmpty {
                ContentUnavailableView {
                    Label("No Radial Menu", systemImage: "circle.grid.cross")
                } description: {
                    Text("Hold a trigger, aim, then release to run an item. Press B to cancel.")
                } actions: {
                    Button("Add Radial Menu") { addMenu() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                radialEditor
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { selectedMenu = menu?.id }
    }

    private var radialEditor: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selectedMenu) {
                    ForEach(profile.radialMenus) { item in
                        Text(item.name)
                            .lineLimit(1)
                            .tag(Optional(item.id))
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    deleteMenu(item.id)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Button {
                        addMenu()
                    } label: {
                        Label("Add Menu", systemImage: "plus")
                    }
                    .disabled(profile.radialMenus.count >= ProfileSanitizer.maxRadialMenus)
                    Spacer()
                }
                .padding(10)
            }
            .frame(width: 220)
            .frame(maxHeight: .infinity)
            Divider()
            ScrollView {
                if let menu {
                    radialForm(menu)
                        .padding(20)
                        .frame(maxWidth: 560, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func addMenu() {
        model.update(profile.id) { profile in
            guard profile.radialMenus.count < ProfileSanitizer.maxRadialMenus else { return }
            let menu = RadialMenu(name: "Menu \(profile.radialMenus.count + 1)", trigger: .menu, selection: .dpad)
            profile.radialMenus.append(menu)
            selectedMenu = menu.id
        }
    }

    private func deleteMenu(_ id: UUID) {
        if selectedMenu == id {
            expandedSlice = nil
        }
        model.update(profile.id) { profile in
            profile.radialMenus.removeAll { $0.id == id }
        }
        if selectedMenu == id {
            selectedMenu = profile.radialMenus.first { $0.id != id }?.id
        }
    }

    private func radialForm(_ menu: RadialMenu) -> some View {
        Form {
            Section("Menu") {
                TextField("Name", text: Binding(
                    get: { menu.name },
                    set: { name in updateMenu(menu.id) { $0.name = name } }
                ))
                Picker("Hold to open", selection: Binding(
                    get: { menu.trigger.id },
                    set: { id in updateMenu(menu.id) { $0.trigger = ControllerButton(id: id) } }
                )) {
                    ForEach(ControllerButton.catalog, id: \.id) { button in
                        Text(button.displayName).tag(button.id)
                    }
                }
                Picker("Aim with", selection: Binding(
                    get: { menu.selection },
                    set: { source in updateMenu(menu.id) { $0.selection = source } }
                )) {
                    ForEach(RadialSelectionSource.allCases, id: \.self) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                Text("Hold the trigger, aim, then release. Press B to cancel. D-Pad uses the hat. On a single Joy-Con that hat is the stick, so the stick aims too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Slices") {
                if menu.items.isEmpty {
                    Text("No slices yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(menu.items) { item in
                    let expanded = expandedSlice == item.id
                    Button {
                        expandedSlice = expanded ? nil : item.id
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.body.weight(.semibold))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label.isEmpty ? "Untitled" : item.label)
                                Text(item.action.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if expanded {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Label", text: Binding(
                                get: { item.label },
                                set: { label in
                                    updateMenu(menu.id) { menu in
                                        guard let index = menu.items.firstIndex(where: { $0.id == item.id }) else { return }
                                        menu.items[index].label = label
                                    }
                                }
                            ))
                            ActionEditor(
                                action: item.action,
                                shortcutNames: model.shortcutNames,
                                onChange: { action in
                                    updateMenu(menu.id) { menu in
                                        guard let index = menu.items.firstIndex(where: { $0.id == item.id }) else { return }
                                        menu.items[index].action = action
                                    }
                                },
                                onTest: { model.test(action: item.action) },
                                onRefreshShortcuts: { model.refreshShortcuts() }
                            )
                            Button("Remove Slice", role: .destructive) {
                                updateMenu(menu.id) { menu in
                                    menu.items.removeAll { $0.id == item.id }
                                }
                                if expandedSlice == item.id {
                                    expandedSlice = nil
                                }
                            }
                        }
                        .padding(.leading, 28)
                        .padding(.bottom, 8)
                    }
                }
                Button("Add Slice") {
                    var newID: UUID?
                    updateMenu(menu.id) { menu in
                        guard menu.items.count < ProfileSanitizer.maxRadialItems else { return }
                        let item = RadialItem(label: "Item", action: .media(.playPause))
                        menu.items.append(item)
                        newID = item.id
                    }
                    if let newID {
                        expandedSlice = newID
                    }
                }
                .disabled(menu.items.count >= ProfileSanitizer.maxRadialItems)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sliceExpanded(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedSlice == id },
            set: { expandedSlice = $0 ? id : nil }
        )
    }

    private func updateMenu(_ id: UUID, _ body: (inout RadialMenu) -> Void) {
        model.update(profile.id) { profile in
            guard let index = profile.radialMenus.firstIndex(where: { $0.id == id }) else { return }
            body(&profile.radialMenus[index])
        }
    }
}

private struct AppsTab: View {
    @EnvironmentObject private var model: AppModel
    let profile: Profile

    var body: some View {
        Form {
            Section("Apps that select this profile") {
                if profile.bundleIdentifiers.isEmpty {
                    Text(profile.isDefault
                         ? "None yet. Automatic switching does not treat this profile as app-specific. It is the fallback when nothing is pinned and no other profile lists the frontmost app."
                         : "None yet. Automatic switching ignores this profile until you add an app. Pin it, or mark it as the default, to use it without an app.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(profile.bundleIdentifiers, id: \.self) { bundle in
                    HStack {
                        Text(bundle)
                        Spacer()
                        Button("Remove") {
                            model.update(profile.id) { profile in
                                profile.bundleIdentifiers.removeAll { $0 == bundle }
                            }
                        }
                    }
                }
                HStack {
                    Button("Add Frontmost") { model.addFrontmostApp(to: profile.id) }
                        .disabled(model.frontmostBundleID == nil)
                    Button("Choose App…") { model.chooseApp(for: profile.id) }
                    Menu("Running Apps") {
                        ForEach(model.runningApps(), id: \.bundleID) { app in
                            Button(app.name) {
                                model.update(profile.id) { profile in
                                    if !profile.bundleIdentifiers.contains(app.bundleID) {
                                        profile.bundleIdentifiers.append(app.bundleID)
                                    }
                                }
                            }
                        }
                    }
                }
                if let bundle = model.frontmostBundleID, let name = model.frontmostName {
                    Text("Frontmost now: \(name) (\(bundle))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DevicesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.controllers.isEmpty {
            ContentUnavailableView(
                "No controller connected",
                systemImage: "gamecontroller",
                description: Text("Pair a Joy-Con, Switch Pro Controller, DualSense, DualShock, or Xbox pad in System Settings, then press a button.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.lastInputName.map { "Last press: \($0)" } ?? "Last press: none yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(model.controllers) { controller in
                        deviceCard(controller)
                    }
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func deviceCard(_ controller: ControllerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.name)
                        .font(.headline)
                    Text(controller.category)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Label(batteryLabel(controller.battery), systemImage: "battery.100")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            Text(controller.hasMotion ? "Motion: available" : "Motion: not reported by macOS")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !controller.pressed.isEmpty {
                Text("Held: \(controller.pressed.joined(separator: ", "))")
                    .font(.caption)
            }
            if !controller.elementNames.isEmpty {
                Text("Inputs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(controller.elementNames, id: \.self) { name in
                        Text(name)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private func batteryLabel(_ value: String?) -> String {
        guard let value, !value.isEmpty, value != "0%" else { return "Battery —" }
        return "Battery \(value)"
    }
}

private struct PermissionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Accessibility") {
                Label(
                    model.accessibilityTrusted ? "Accessibility is on" : "Accessibility is off",
                    systemImage: model.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                Text("macOS requires Accessibility before this app can type or move the pointer. After you allow it, quit and reopen Gamepad Keymapper. Shortcuts and app launch work without it.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Accessibility Settings") { model.openAccessibilitySettings() }
                        .help("After you turn it on, quit and reopen Gamepad Keymapper.")
                    Button("Check Again") { model.refreshAccessibility(prompt: false) }
                    if !model.settings.didFinishOnboarding {
                        Button("Start Mapping") { model.finishOnboarding() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            Section("Mapping") {
                Toggle("Mapping enabled", isOn: Binding(
                    get: { model.settings.mappingEnabled },
                    set: { model.setMappingEnabled($0) }
                ))
                HStack {
                    Text("Button debounce")
                    Slider(value: Binding(
                        get: { model.settings.debounceMilliseconds },
                        set: { model.settings.debounceMilliseconds = $0; model.noteTuningChanged() }
                    ), in: 0...80)
                    Text("\(Int(model.settings.debounceMilliseconds)) ms")
                        .frame(width: 48, alignment: .trailing)
                }
                HStack {
                    Text("Stick deadzone")
                    Slider(value: Binding(
                        get: { model.settings.stickDeadzone },
                        set: {
                            model.settings.stickDeadzone = $0
                            if model.settings.stickReleaseZone > $0 {
                                model.settings.stickReleaseZone = $0 * 0.7
                            }
                            model.noteTuningChanged()
                        }
                    ), in: 0.05...0.8)
                }
            }
            Section("Login") {
                Toggle("Open at login", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Text("Starts in the menu bar only. The editor stays closed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.loginItemNeedsApproval {
                    Text("macOS is waiting for approval. Allow Gamepad Keymapper in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Login Items Settings") { model.openLoginItemsSettings() }
                }
            }
            Section("Profiles on disk") {
                Text("Profiles are stored as JSON in Application Support. Import and export are in the toolbar. Files are checked for size, counts, and safe Shortcut names and app paths.")
                    .foregroundStyle(.secondary)
                Button("Restore Sample Profiles") { model.resetToSample() }
            }
            if let status = model.statusMessage {
                Section {
                    Text(status)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.syncLaunchAtLogin() }
    }
}
