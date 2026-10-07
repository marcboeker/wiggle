import SwiftUI

/// The writes a settings page can make. A page never touches the store or
/// the system directly.
struct SettingsActions {
    var setOpacity: (CGFloat) -> Void
    var resetOpacity: () -> Void
    var setBackgroundOpacity: (CGFloat) -> Void
    var resetBackgroundOpacity: () -> Void
    var setLaunchAtLogin: (Bool) -> Void
    var refreshLoginItemStatus: () -> Void
    var openLoginItemsSettings: () -> Void
    var setShowsMenuBarItem: (Bool) -> Void
    var setTriggers: (Set<TriggerKind>) -> Void
    var setTriggerShortcut: (TriggerShortcut) -> Void
    var openTrackpadSettings: () -> Void
    var setOverlayAppearance: (OverlayAppearance) -> Void
}

struct SettingsRootView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case general = "General", actions = "Actions", triggers = "Triggers"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .actions: "circle.circle"
            case .triggers: "hand.tap"
            }
        }
    }

    @Bindable var model: SettingsModel
    let wheelPane: WheelPaneViewController
    let actions: SettingsActions

    @State private var selection: Page? = .general

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, id: \.self, selection: $selection) { page in
                Label(page.rawValue, systemImage: page.symbol)
            }
            .navigationSplitViewColumnWidth(180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            // The titlebar is transparent and empty, so the page title starts
            // at the top edge.
            Group {
                switch selection ?? .general {
                case .general: GeneralPage(model: model, actions: actions)
                case .actions: ActionsPage(wheelPane: wheelPane)
                case .triggers: TriggersPage(model: model, actions: actions)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
    }
}

private struct PageTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let description: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        LabeledContent {
            control()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct GeneralPage: View {
    @Bindable var model: SettingsModel
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                SettingsRow(title: "Overlay opacity", description: "How see-through the whole wheel is when it opens.") {
                    opacityControl
                }
                SettingsRow(
                    title: "Background opacity",
                    description: "How see-through the blurred disc behind the tiles is."
                ) {
                    backgroundOpacityControl
                }
                SettingsRow(
                    title: "Overlay appearance",
                    description: "Whether the wheel is light or dark, or follows the system setting."
                ) {
                    appearanceControl
                }
                SettingsRow(title: "Launch at login", description: launchAtLoginDescription) {
                    launchAtLoginControl
                }
                SettingsRow(
                    title: "Show menu bar item",
                    description: "Adds a menu bar item with Settings and Quit Wiggle."
                ) {
                    Toggle(
                        "Show menu bar item", isOn: Binding(
                            get: { model.showsMenuBarItem }, set: { actions.setShowsMenuBarItem($0) })
                    )
                    .labelsHidden()
                }
            } header: {
                PageTitle(title: "General")
            }
        }
        .formStyle(.grouped)
        .onAppear { actions.refreshLoginItemStatus() }
    }

    private var opacityControl: some View {
        HStack(spacing: 12) {
            Slider(
                value: $model.overlayOpacity, in: Config.overlayOpacityRange,
                onEditingChanged: { editing in
                    if !editing { actions.setOpacity(model.overlayOpacity) }
                }
            )
            .frame(width: 160)
            .accessibilityLabel("Overlay Opacity")
            Text("\(Int((model.overlayOpacity * 100).rounded())) %")
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
            Button("Reset") { actions.resetOpacity() }
        }
    }

    private var backgroundOpacityControl: some View {
        HStack(spacing: 12) {
            Slider(
                value: $model.backgroundOpacity, in: Config.backgroundOpacityRange,
                onEditingChanged: { editing in
                    if !editing { actions.setBackgroundOpacity(model.backgroundOpacity) }
                }
            )
            .frame(width: 160)
            .accessibilityLabel("Background Opacity")
            Text("\(Int((model.backgroundOpacity * 100).rounded())) %")
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
            Button("Reset") { actions.resetBackgroundOpacity() }
        }
    }

    private var appearanceControl: some View {
        Picker(
            "Overlay Appearance", selection: Binding(
                get: { model.overlayAppearance }, set: { actions.setOverlayAppearance($0) })
        ) {
            ForEach(OverlayAppearance.allCases, id: \.self) { appearance in
                Text(appearance.title).tag(appearance)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 200)
    }

    private var launchAtLoginControl: some View {
        HStack(spacing: 8) {
            if model.loginItemStatus == .requiresApproval {
                Button("Open Login Items…") { actions.openLoginItemsSettings() }
            }
            Toggle(
                "Launch at login", isOn: Binding(
                    get: { model.loginItemStatus == .enabled || model.loginItemStatus == .requiresApproval },
                    set: { actions.setLaunchAtLogin($0) })
            )
            .labelsHidden()
        }
    }

    private var launchAtLoginDescription: String {
        model.loginItemStatus == .requiresApproval
            ? "Needs approval in System Settings › Login Items."
            : "Opens Wiggle automatically when you log in."
    }
}

struct ActionsPage: View {
    let wheelPane: WheelPaneViewController

    var body: some View {
        VStack(spacing: 0) {
            // Matches where a grouped Form puts the header on the other pages.
            PageTitle(title: "Actions")
                .padding(.top, 20)
                .padding(.leading, 30)
                .padding(.trailing)
            Spacer(minLength: 0)
            WheelPaneRepresentable(viewController: wheelPane)
                .frame(width: WheelPaneViewController.paneSize.width, height: WheelPaneViewController.paneSize.height)
            Spacer(minLength: 0)
        }
    }
}

struct TriggersPage: View {
    @Bindable var model: SettingsModel
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                ForEach(TriggerKind.allCases, id: \.self) { kind in
                    SettingsRow(title: kind.title, description: kind.description) {
                        HStack(spacing: 12) {
                            if kind == .shortcut {
                                TriggerShortcutField(
                                    shortcut: model.triggerShortcut,
                                    onChange: actions.setTriggerShortcut)
                            }
                            Toggle(kind.title, isOn: binding(for: kind))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(model.triggers == [kind])
                        }
                    }
                }
            } header: {
                PageTitle(title: "Triggers")
            }
            if model.showsSwipeNote {
                Section { swipeNote }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for kind: TriggerKind) -> Binding<Bool> {
        Binding(
            get: { model.triggers.contains(kind) },
            set: { isOn in
                var triggers = model.triggers
                if isOn { triggers.insert(kind) } else { triggers.remove(kind) }
                actions.setTriggers(triggers)
            })
    }

    private var swipeNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("macOS also uses this swipe for Mission Control and App Exposé.")
                .font(.callout)
                .foregroundStyle(.orange)
            Button("Open Trackpad Settings…") { actions.openTrackpadSettings() }
        }
    }
}
