import SwiftUI
import GamepadKeymapperCore

struct EditorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 880, minHeight: 580)
        .onChange(of: model.sidebar) { _, item in
            model.engine.setDevicesVisible(item == .devices)
        }
        .alert("Gamepad Keymapper", isPresented: alertShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Import") { model.importProfiles() }
                Button("Export") { model.exportProfiles() }
            }
        }
    }

    private var alertShown: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }

    private var sidebar: some View {
        List(selection: $model.sidebar) {
            Section("Profiles") {
                ForEach(model.document.profiles) { profile in
                    HStack {
                        Text(profile.name)
                        Spacer()
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
            Section("Library") {
                Label("Devices", systemImage: "gamecontroller")
                    .tag(SidebarItem.devices)
                Label("Permissions", systemImage: "lock.shield")
                    .tag(SidebarItem.permissions)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            header
            Divider()
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

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill")
                .foregroundStyle(Color.accentColor)
            Text("All features are included. Nothing is locked, trialed, or sold.")
                .font(.callout)
            Spacer()
            if let name = model.frontmostName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct ProfileEditor: View {
    @EnvironmentObject private var model: AppModel
    let profileID: UUID

    private var profile: Profile? {
        model.document.profiles.first { $0.id == profileID }
    }

    var body: some View {
        if let profile {
            VStack(alignment: .leading, spacing: 0) {
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
    }

    private func profileHeader(_ profile: Profile) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Profile name", text: Binding(
                    get: { profile.name },
                    set: { name in model.update(profile.id) { $0.name = name } }
                ))
                .font(.title2)
                .textFieldStyle(.plain)
                Text(profile.isDefault ? "Fallback when no app-specific profile matches." : "Used when one of its apps is frontmost.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Enabled", isOn: Binding(
                get: { profile.enabled },
                set: { enabled in model.update(profile.id) { $0.enabled = enabled } }
            ))
            Toggle("Default", isOn: Binding(
                get: { profile.isDefault },
                set: { isDefault in if isDefault { model.makeDefault(profile.id) } }
            ))
            Button("Duplicate") { model.duplicate(profileID: profile.id) }
                .disabled(model.document.profiles.count >= ProfileSanitizer.maxProfiles)
            Button("Delete", role: .destructive) { model.delete(profileID: profile.id) }
                .disabled(model.document.profiles.count < 2)
        }
        .padding(16)
    }
}

private struct BindingsTab: View {
    @EnvironmentObject private var model: AppModel
    let profile: Profile
    @State private var selectedBinding: UUID?

    private var layer: Layer? {
        if let id = model.editingLayerID, let match = profile.layers.first(where: { $0.id == id }) {
            return match
        }
        return profile.layers.first
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                if let layer {
                    Picker("Layer", selection: layerSelection) {
                        ForEach(profile.layers) { item in
                            Text(layerTitle(item)).tag(Optional(item.id))
                        }
                    }
                    .labelsHidden()
                    HStack {
                        Button("Add Layer") { model.addLayer(to: profile.id) }
                            .disabled(profile.layers.count >= ProfileSanitizer.maxLayers)
                        Button("Delete Layer") {
                            if let id = layer.id as UUID? {
                                model.deleteLayer(profileID: profile.id, layerID: id)
                            }
                        }
                        .disabled(profile.layers.count < 2 || isBase(layer))
                        Spacer()
                        Button("Add Binding") {
                            model.editingLayerID = layer.id
                            model.addBinding(profileID: profile.id, layerID: layer.id)
                        }
                        .disabled(layer.bindings.count >= ProfileSanitizer.maxBindings)
                    }
                    layerActivation(layer)
                    List(selection: $selectedBinding) {
                        ForEach(layer.bindings) { binding in
                            HStack {
                                Text(binding.button.displayName)
                                    .frame(width: 170, alignment: .leading)
                                Text(binding.action.summary)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                if model.captureBindingID == binding.id {
                                    Text("Press a button…")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .tag(Optional(binding.id))
                            .contextMenu {
                                Button("Delete") {
                                    model.deleteBinding(profileID: profile.id, layerID: layer.id, bindingID: binding.id)
                                }
                            }
                        }
                    }
                    if !profile.validationWarnings().isEmpty {
                        ForEach(profile.validationWarnings(), id: \.self) { warning in
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
            .padding(12)
            .frame(minWidth: 420)

            Group {
                if let layer, let binding = layer.bindings.first(where: { $0.id == selectedBinding }) {
                    inspector(layer: layer, binding: binding)
                } else {
                    ContentUnavailableView("Select a Binding", systemImage: "hand.tap", description: Text("Choose a row, or add a binding and press a controller button."))
                }
            }
            .frame(minWidth: 300, idealWidth: 360)
            .padding(16)
        }
        .onAppear {
            model.editingLayerID = layer?.id ?? profile.layers.first?.id
            if selectedBinding == nil {
                selectedBinding = layer?.bindings.first?.id
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

    private func inspector(layer: Layer, binding: Binding) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(binding.button.displayName)
                    .font(.headline)
                HStack {
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
                        }
                    )) {
                        ForEach(ControllerButton.catalog, id: \.id) { button in
                            Text(button.displayName).tag(button.id)
                        }
                    }
                    Button(model.captureBindingID == binding.id ? "Listening…" : "Capture") {
                        model.editingLayerID = layer.id
                        model.beginCapture(bindingID: binding.id)
                    }
                }
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
                    selectedBinding = nil
                }
            }
        }
    }

    private func layerActivation(_ layer: Layer) -> some View {
        HStack {
            if case .base = layer.activation {
                Text("Base layer is always on. Other layers replace it while they are active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Activation", selection: activationKind(layer)) {
                    Text("Hold").tag("hold")
                    Text("Toggle").tag("toggle")
                }
                .frame(width: 160)
                Picker("Modifier", selection: activatorBinding(layer)) {
                    ForEach(ControllerButton.catalog, id: \.id) { button in
                        Text(button.displayName).tag(button.id)
                    }
                }
            }
            Spacer()
            if layer.activation.activator != nil {
                Toggle("Fall through", isOn: Binding(
                    get: { layer.allowsFallthrough },
                    set: { value in
                        model.update(profile.id) { profile in
                            guard let index = profile.layers.firstIndex(where: { $0.id == layer.id }) else { return }
                            profile.layers[index].allowsFallthrough = value
                        }
                    }
                ))
                .help("Unmapped buttons keep their base-layer action.")
            }
        }
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
            return layer.name
        case .hold(let button):
            return "\(layer.name) — Hold \(button.displayName)"
        case .toggle(let button):
            return "\(layer.name) — Toggle \(button.displayName)"
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
        HStack {
            Text(title)
                .frame(width: 120, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: range)
            Text(value, format: .number.precision(.fractionLength(0...2)))
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)
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

    private var menu: RadialMenu? {
        if let selectedMenu, let match = profile.radialMenus.first(where: { $0.id == selectedMenu }) {
            return match
        }
        return profile.radialMenus.first
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                List(selection: $selectedMenu) {
                    ForEach(profile.radialMenus) { item in
                        Text(item.name).tag(Optional(item.id))
                    }
                }
                HStack {
                    Button("Add Menu") {
                        model.update(profile.id) { profile in
                            guard profile.radialMenus.count < ProfileSanitizer.maxRadialMenus else { return }
                            let menu = RadialMenu(name: "Menu \(profile.radialMenus.count + 1)", trigger: .menu, selection: .dpad)
                            profile.radialMenus.append(menu)
                            selectedMenu = menu.id
                        }
                    }
                    Button("Delete Menu") {
                        guard let id = menu?.id else { return }
                        model.update(profile.id) { profile in
                            profile.radialMenus.removeAll { $0.id == id }
                        }
                    }
                    .disabled(menu == nil)
                }
                .padding(8)
            }
            .frame(minWidth: 200, idealWidth: 240)
            if let menu {
                Form {
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
                    Text("Hold the trigger, aim, then release to run the highlighted item. Press B to cancel. Release with nothing highlighted to cancel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(menu.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Label", text: Binding(
                                get: { item.label },
                                set: { label in
                                    updateMenu(menu.id) { menu in
                                        guard let index = menu.items.firstIndex(where: { $0.id == item.id }) else { return }
                                        menu.items[index].label = label
                                    }
                                }
                            ))
                            Text(item.action.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                            Button("Remove Item") {
                                updateMenu(menu.id) { menu in
                                    menu.items.removeAll { $0.id == item.id }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Button("Add Item") {
                        updateMenu(menu.id) { menu in
                            guard menu.items.count < ProfileSanitizer.maxRadialItems else { return }
                            menu.items.append(RadialItem(label: "Item", action: .media(.playPause)))
                        }
                    }
                    .disabled(menu.items.count >= ProfileSanitizer.maxRadialItems)
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView(
                    "No Radial Menu",
                    systemImage: "circle.grid.cross",
                    description: Text("Add a menu, then hold its trigger and aim with a stick or the D-pad.")
                )
            }
        }
        .onAppear { selectedMenu = menu?.id }
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
            Section("This profile turns on for") {
                if profile.bundleIdentifiers.isEmpty {
                    Text(profile.isDefault
                         ? "No apps are listed, so this profile is the fallback."
                         : "Add an app. Until you do, this profile is only used if you pin it from the menu bar.")
                        .foregroundStyle(.secondary)
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
            List(model.controllers) { controller in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(controller.name).font(.headline)
                        Spacer()
                        if let battery = controller.battery {
                            Text(battery).foregroundStyle(.secondary)
                        }
                    }
                    Text(controller.category).font(.subheadline).foregroundStyle(.secondary)
                    Text(controller.hasMotion ? "Motion: available" : "Motion: not reported by macOS")
                        .font(.caption)
                    if !controller.pressed.isEmpty {
                        Text("Held: \(controller.pressed.joined(separator: ", "))")
                            .font(.caption)
                    }
                    if !controller.elementNames.isEmpty {
                        Text(controller.elementNames.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }
        }
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
                Text("macOS requires Accessibility before an app can create keyboard and mouse events. Gamepad Keymapper uses it only for the actions you bind. Shortcuts and app launch work without it.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Accessibility Settings") { model.openAccessibilitySettings() }
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
                Toggle("Open at login", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
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
    }
}
