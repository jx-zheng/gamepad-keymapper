import AppKit
import Combine
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case profile(UUID)
    case devices
    case permissions
}

enum EditorTab: String, CaseIterable, Identifiable {
    case bindings = "Bindings"
    case pointer = "Pointer"
    case radial = "Radial Menus"
    case apps = "Apps"

    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    static weak var shared: AppModel?

    @Published var document: ProfileDocument
    @Published var settings: AppSettings
    @Published var controllers: [ControllerSnapshot] = []
    @Published var frontmostBundleID: String?
    @Published var frontmostName: String?
    @Published var activeProfileID: UUID?
    @Published var accessibilityTrusted = false
    @Published var statusMessage: String?
    /// Last controller button that went down, whether or not macOS allowed the injected event.
    @Published var lastInputName: String?
    @Published var alertMessage: String?
    @Published var sidebar: SidebarItem
    @Published var editorTab: EditorTab = .bindings
    @Published var editingLayerID: UUID?
    @Published var captureBindingID: UUID?
    @Published var shortcutNames: [String] = []
    @Published var importWarnings: [String] = []

    let engine = MappingEngine()
    private let store: ProfileStore
    private let frontmost = FrontmostAppMonitor()
    private var persistTask: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    /// True when the on-disk profile file could not be read, so autosave stays off.
    @Published private(set) var savesDisabled = false
    private var suppressAutosave = false
    private var archiveUnreadableOnNextSave = false
    private var sleepObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    init() {
        let store = ProfileStore(root: ProfileStore.applicationSupportRoot())
        self.store = store
        var loadedSettings = AppSettings.initial
        var loadedDocument = SampleProfiles.document()
        var failedToLoadProfiles = false
        var loadFailureMessage: String?
        do {
            loadedSettings = try store.loadSettings()
        } catch {
            loadedSettings = .initial
        }
        do {
            loadedDocument = try store.loadDocument()
        } catch {
            loadedDocument = SampleProfiles.document()
            failedToLoadProfiles = true
            loadFailureMessage = "Couldn’t read saved profiles (\(error.localizedDescription)). The file on disk was left unchanged."
        }
        if loadedDocument.profiles.isEmpty {
            loadedDocument = SampleProfiles.document()
        }
        document = loadedDocument
        settings = loadedSettings
        if let first = loadedDocument.profiles.first(where: \.isDefault) ?? loadedDocument.profiles.first {
            sidebar = .profile(first.id)
            editingLayerID = first.layers.first?.id
        } else {
            sidebar = .permissions
        }
        suppressAutosave = failedToLoadProfiles
        savesDisabled = failedToLoadProfiles
        archiveUnreadableOnNextSave = failedToLoadProfiles
        alertMessage = loadFailureMessage
        AppModel.shared = self
        wireEngine()
        frontmost.onChange = { [weak self] bundle, name in
            Task { @MainActor in
                self?.noteFrontmost(bundle: bundle, name: name)
            }
        }
        frontmost.start()
        engine.start()
        refreshAccessibility(prompt: false)
        pushProfile()
        // Register after init returns. A Task that captures self here is still the
        // initializing self, and the Swift 6 compiler rejects that capture.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.startLifetimeObservers()
            self.syncLaunchAtLogin()
            if !self.settings.didFinishOnboarding || !self.accessibilityTrusted {
                self.showEditor()
            }
        }
    }

    private func startLifetimeObservers() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.engine.releaseHeldInputs()
            }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccessibility(prompt: false)
            }
        }
    }

    var activeProfileName: String {
        document.profiles.first { $0.id == activeProfileID }?.name ?? "No profile"
    }

    var statusLine: String {
        let mapping = settings.mappingEnabled ? "On" : "Off"
        let pads = controllers.count == 1 ? "1 controller" : "\(controllers.count) controllers"
        return "\(mapping) · \(activeProfileName) · \(pads)"
    }

    func showEditor() {
        EditorWindow.show(model: self)
    }

    func shutdown() {
        persistNow()
        frontmost.stop()
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
        engine.shutdown()
    }

    func setMappingEnabled(_ enabled: Bool) {
        settings.mappingEnabled = enabled
        pushTuning()
        schedulePersist()
    }

    func pin(profileID: UUID) {
        settings.profileOverrideID = profileID
        pushProfile()
        schedulePersist()
    }

    func clearOverride() {
        settings.profileOverrideID = nil
        pushProfile()
        schedulePersist()
    }

    func refreshAccessibility(prompt: Bool) {
        accessibilityTrusted = AccessibilityPermission.isTrusted(prompt: prompt)
        engine.invalidateTrust()
    }

    func openAccessibilitySettings() {
        AccessibilityPermission.openSettings()
    }

    func finishOnboarding() {
        refreshAccessibility(prompt: false)
        guard accessibilityTrusted else {
            openAccessibilitySettings()
            return
        }
        settings.didFinishOnboarding = true
        schedulePersist()
        if case .permissions = sidebar, let id = document.profiles.first?.id {
            sidebar = .profile(id)
        }
    }

    /// A mapped key or click was blocked. Re-open the editor so the Accessibility banner is visible.
    func noteInjectionBlocked() {
        refreshAccessibility(prompt: false)
        guard !accessibilityTrusted else { return }
        if !EditorWindow.isOpen {
            showEditor()
        }
    }

    /// True when macOS has the login item registered but the user still has to allow it.
    @Published private(set) var loginItemNeedsApproval = false

    /// Matches the toggle to `SMAppService` without opening the editor.
    func syncLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        loginItemNeedsApproval = status == .requiresApproval
        let enabled = status == .enabled || status == .requiresApproval
        guard settings.launchAtLogin != enabled else { return }
        settings.launchAtLogin = enabled
        schedulePersist()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            let status = SMAppService.mainApp.status
            if enabled {
                if status != .enabled && status != .requiresApproval {
                    try SMAppService.mainApp.register()
                }
            } else if status == .enabled || status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            alertMessage = "Couldn’t update the login item. \(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        loginItemNeedsApproval = status == .requiresApproval
        settings.launchAtLogin = status == .enabled || status == .requiresApproval
        schedulePersist()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func update(_ id: UUID, _ body: (inout Profile) -> Void) {
        guard let index = document.profiles.firstIndex(where: { $0.id == id }) else { return }
        body(&document.profiles[index])
        schedulePersist()
        schedulePush()
    }

    func addProfile() {
        guard document.profiles.count < ProfileSanitizer.maxProfiles else { return }
        let profile = Profile.starter(name: "Profile \(document.profiles.count + 1)", isDefault: document.profiles.isEmpty)
        document.profiles.append(profile)
        sidebar = .profile(profile.id)
        editingLayerID = profile.layers.first?.id
        schedulePersist()
        schedulePush()
    }

    func duplicate(profileID: UUID) {
        guard document.profiles.count < ProfileSanitizer.maxProfiles else { return }
        guard let profile = document.profiles.first(where: { $0.id == profileID }) else { return }
        let copy = duplicated(profile)
        document.profiles.append(copy)
        sidebar = .profile(copy.id)
        editingLayerID = copy.layers.first?.id
        schedulePersist()
    }

    func delete(profileID: UUID) {
        guard document.profiles.count > 1 else { return }
        document.profiles.removeAll { $0.id == profileID }
        if !document.profiles.contains(where: \.isDefault), let first = document.profiles.indices.first {
            document.profiles[first].isDefault = true
        }
        if settings.profileOverrideID == profileID {
            settings.profileOverrideID = nil
        }
        if case .profile(let selected) = sidebar, selected == profileID {
            sidebar = .profile(document.profiles[0].id)
        }
        schedulePersist()
        schedulePush()
    }

    func makeDefault(_ id: UUID) {
        for index in document.profiles.indices {
            document.profiles[index].isDefault = document.profiles[index].id == id
        }
        schedulePersist()
        schedulePush()
    }

    func addLayer(to profileID: UUID) {
        guard let existing = document.profiles.first(where: { $0.id == profileID }),
              existing.layers.count < ProfileSanitizer.maxLayers else { return }
        update(profileID) { profile in
            guard profile.layers.count < ProfileSanitizer.maxLayers else { return }
            let used = profile.layerActivatorIDs
            let activator: ControllerButton = used.contains(ControllerButton.leftShoulder.id) ? .options : .leftShoulder
            let layer = Layer(name: "Layer \(profile.layers.count + 1)", activation: .hold(activator))
            profile.layers.append(layer)
            editingLayerID = layer.id
        }
    }

    func deleteLayer(profileID: UUID, layerID: UUID) {
        let capturingThisLayer = captureBindingID != nil && editingLayerID == layerID
        update(profileID) { profile in
            guard profile.layers.count > 1 else { return }
            profile.layers.removeAll { $0.id == layerID }
            if editingLayerID == layerID {
                editingLayerID = profile.layers.first?.id
            }
        }
        if capturingThisLayer {
            disarmCapture()
        }
    }

    func addBinding(profileID: UUID, layerID: UUID) {
        guard let existing = document.profiles.first(where: { $0.id == profileID }),
              let layer = existing.layers.first(where: { $0.id == layerID }),
              layer.bindings.count < ProfileSanitizer.maxBindings else { return }
        var newID: UUID?
        update(profileID) { profile in
            guard let index = profile.layers.firstIndex(where: { $0.id == layerID }),
                  profile.layers[index].bindings.count < ProfileSanitizer.maxBindings else { return }
            let binding = ButtonBinding(button: .a, action: .mouseClick(.left, clicks: 1))
            profile.layers[index].bindings.append(binding)
            newID = binding.id
        }
        if let newID {
            captureBindingID = newID
            engine.armCapture()
        }
    }

    func deleteBinding(profileID: UUID, layerID: UUID, bindingID: UUID) {
        update(profileID) { profile in
            guard let index = profile.layers.firstIndex(where: { $0.id == layerID }) else { return }
            profile.layers[index].bindings.removeAll { $0.id == bindingID }
        }
        if captureBindingID == bindingID {
            disarmCapture()
        }
    }

    func disarmCapture() {
        captureBindingID = nil
        engine.disarmCapture()
    }

    func beginCapture(bindingID: UUID) {
        captureBindingID = bindingID
        engine.armCapture()
    }

    func applyCapture(_ button: ControllerButton) {
        guard let bindingID = captureBindingID, case .profile(let profileID) = sidebar, let layerID = editingLayerID else {
            disarmCapture()
            return
        }
        update(profileID) { profile in
            guard let layerIndex = profile.layers.firstIndex(where: { $0.id == layerID }),
                  let bindingIndex = profile.layers[layerIndex].bindings.firstIndex(where: { $0.id == bindingID }) else { return }
            profile.layers[layerIndex].bindings[bindingIndex].button = button
        }
        captureBindingID = nil
    }

    /// Sets the action for a control, creating the binding the first time it is mapped.
    func setActionForButton(profileID: UUID, layerID: UUID, button: ControllerButton, action: MapperAction) {
        update(profileID) { profile in
            guard let layerIndex = profile.layers.firstIndex(where: { $0.id == layerID }) else { return }
            if let bindingIndex = profile.layers[layerIndex].bindings.firstIndex(where: { $0.button.id == button.id }) {
                profile.layers[layerIndex].bindings[bindingIndex].action = action
            } else if profile.layers[layerIndex].bindings.count < ProfileSanitizer.maxBindings {
                profile.layers[layerIndex].bindings.append(ButtonBinding(button: button, action: action))
            }
        }
    }

    func setAction(profileID: UUID, layerID: UUID, bindingID: UUID, action: MapperAction) {
        update(profileID) { profile in
            guard let layerIndex = profile.layers.firstIndex(where: { $0.id == layerID }),
                  let bindingIndex = profile.layers[layerIndex].bindings.firstIndex(where: { $0.id == bindingID }) else { return }
            profile.layers[layerIndex].bindings[bindingIndex].action = action
        }
    }

    func test(action: MapperAction) {
        engine.test(action)
    }

    func refreshShortcuts() {
        ShortcutRunner.shared.list { [weak self] names in
            self?.shortcutNames = names
        }
    }

    func addFrontmostApp(to profileID: UUID) {
        guard let bundle = frontmostBundleID, ProfileSanitizer.isBundleIdentifier(bundle) else { return }
        update(profileID) { profile in
            if !profile.bundleIdentifiers.contains(where: { $0.caseInsensitiveCompare(bundle) == .orderedSame }) {
                profile.bundleIdentifiers.append(bundle)
            }
        }
    }

    func chooseApp(for profileID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose an app. Its bundle id is stored in this profile."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundle = Bundle(url: url)?.bundleIdentifier
        update(profileID) { profile in
            if let bundle, ProfileSanitizer.isBundleIdentifier(bundle) {
                if !profile.bundleIdentifiers.contains(where: { $0.caseInsensitiveCompare(bundle) == .orderedSame }) {
                    profile.bundleIdentifiers.append(bundle)
                }
            }
        }
    }

    func importProfiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let report = try ProfileCodec.importDocument(data)
            let merged = document.merging(report.document)
            let sanitized = try ProfileSanitizer.sanitize(merged)
            document = sanitized.document
            importWarnings = report.warnings + sanitized.warnings
            if !importWarnings.isEmpty {
                alertMessage = importWarnings.prefix(4).joined(separator: "\n")
            }
            suppressAutosave = false
            savesDisabled = false
            persistNow()
            pushProfile()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func exportProfiles() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "gamepad-keymapper-profiles.json"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let clean = try ProfileSanitizer.sanitize(document).document
            try ProfileCodec.encode(clean).write(to: url, options: .atomic)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func resetToSample() {
        let alert = NSAlert()
        alert.messageText = "Restore sample profiles?"
        alert.informativeText = "This replaces the profiles in the editor. If the saved file could not be read, a copy is kept beside it before anything new is written."
        alert.addButton(withTitle: "Restore Sample")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        document = SampleProfiles.document()
        settings.profileOverrideID = nil
        suppressAutosave = false
        savesDisabled = false
        if let first = document.profiles.first {
            sidebar = .profile(first.id)
            editingLayerID = first.layers.first?.id
        }
        persistNow()
        pushProfile()
    }

    func runningApps() -> [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let bundle = app.bundleIdentifier else { return nil }
            guard bundle != Bundle.main.bundleIdentifier else { return nil }
            guard ProfileSanitizer.isBundleIdentifier(bundle) else { return nil }
            return (app.localizedName ?? bundle, bundle)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func noteFrontmost(bundle: String?, name: String?) {
        frontmostBundleID = bundle
        frontmostName = name
        pushProfile()
    }

    private func wireEngine() {
        engine.onControllers = { [weak self] snapshots in
            Task { @MainActor in
                guard let self else { return }
                let gainedController = self.controllers.isEmpty && !snapshots.isEmpty
                self.controllers = snapshots
                if gainedController && !self.accessibilityTrusted {
                    self.refreshAccessibility(prompt: false)
                    if !self.accessibilityTrusted {
                        self.showEditor()
                    }
                }
            }
        }
        engine.onCapture = { [weak self] button in
            Task { @MainActor in self?.applyCapture(button) }
        }
        engine.onStatus = { [weak self] message in
            Task { @MainActor in self?.statusMessage = message }
        }
        engine.onInput = { [weak self] name in
            Task { @MainActor in self?.lastInputName = name }
        }
        engine.onInjectionBlocked = { [weak self] in
            Task { @MainActor in self?.noteInjectionBlocked() }
        }
    }

    private func schedulePersist() {
        guard !suppressAutosave else { return }
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run { self?.persistNow() }
        }
    }

    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            await MainActor.run { self?.pushProfile() }
        }
    }

    func noteTuningChanged() {
        pushTuning()
        schedulePersist()
    }

    private func persistNow() {
        guard !suppressAutosave else { return }
        if archiveUnreadableOnNextSave {
            do {
                try archiveUnreadableProfiles()
            } catch {
                savesDisabled = true
                suppressAutosave = true
                alertMessage = "Couldn’t keep a copy of the unreadable profiles file (\(error.localizedDescription)). Saving stays off."
                return
            }
            archiveUnreadableOnNextSave = false
        }
        do {
            // Sanitize the bytes written to disk. Do not write that copy back into the
            // live document, or a half-typed bundle id or name is trimmed mid-edit.
            try store.saveDocument(document)
            try store.saveSettings(settings)
        } catch {
            statusMessage = "Couldn’t save profiles."
        }
    }

    /// Copies the unreadable file aside before the first write that would replace it.
    private func archiveUnreadableProfiles() throws {
        let source = store.profilesURL
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let stamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let destination = source.deletingLastPathComponent()
            .appendingPathComponent("profiles.unreadable-\(stamp)-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func pushProfile() {
        let selected = ProfileSelector.select(
            from: document.profiles,
            frontmostBundleID: frontmostBundleID,
            overrideID: settings.profileOverrideID
        )
        activeProfileID = selected?.id
        engine.setProfile(selected)
        pushTuning()
    }

    private func pushTuning() {
        engine.setTuning(
            debounce: settings.debounceMilliseconds / 1000,
            deadzone: settings.stickDeadzone,
            release: settings.stickReleaseZone,
            enabled: settings.mappingEnabled
        )
    }

    private func duplicated(_ profile: Profile) -> Profile {
        var copy = profile
        copy.id = UUID()
        copy.name = "\(profile.name) Copy"
        copy.isDefault = false
        copy.layers = profile.layers.map { layer in
            var layer = layer
            layer.id = UUID()
            layer.bindings = layer.bindings.map { binding in
                var binding = binding
                binding.id = UUID()
                return binding
            }
            return layer
        }
        copy.radialMenus = profile.radialMenus.map { menu in
            var menu = menu
            menu.id = UUID()
            menu.items = menu.items.map { item in
                var item = item
                item.id = UUID()
                return item
            }
            return menu
        }
        return copy
    }
}
