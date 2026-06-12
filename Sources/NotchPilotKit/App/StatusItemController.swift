import AppKit
import Combine
import KeyboardShortcuts

public struct StatusItemLyricsActions {
    let search: () -> Void
    let ignoreCurrentTrack: () -> Void
    let revealCurrentLyricsInFinder: () -> Void
    let canSearchCurrentTrack: () -> Bool
    let canIgnoreCurrentTrack: () -> Bool
    let canRevealCurrentLyricsInFinder: () -> Bool
    let canAdjustOffset: () -> Bool
    let getOffset: () -> Int
    let setOffset: (Int) -> Void

    public init(
        search: @escaping () -> Void,
        ignoreCurrentTrack: @escaping () -> Void,
        revealCurrentLyricsInFinder: @escaping () -> Void,
        canSearchCurrentTrack: @escaping () -> Bool,
        canIgnoreCurrentTrack: @escaping () -> Bool,
        canRevealCurrentLyricsInFinder: @escaping () -> Bool,
        canAdjustOffset: @escaping () -> Bool,
        getOffset: @escaping () -> Int,
        setOffset: @escaping (Int) -> Void
    ) {
        self.search = search
        self.ignoreCurrentTrack = ignoreCurrentTrack
        self.revealCurrentLyricsInFinder = revealCurrentLyricsInFinder
        self.canSearchCurrentTrack = canSearchCurrentTrack
        self.canIgnoreCurrentTrack = canIgnoreCurrentTrack
        self.canRevealCurrentLyricsInFinder = canRevealCurrentLyricsInFinder
        self.canAdjustOffset = canAdjustOffset
        self.getOffset = getOffset
        self.setOffset = setOffset
    }
}

public struct StatusItemActivitySneakActions {
    let isHidden: () -> Bool
    let toggle: () -> Void

    public init(isHidden: @escaping () -> Bool, toggle: @escaping () -> Void) {
        self.isHidden = isHidden
        self.toggle = toggle
    }
}

@MainActor
public final class StatusItemController: NSObject, NSMenuItemValidation {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    private let lyricsActions: StatusItemLyricsActions
    private let activitySneakActions: StatusItemActivitySneakActions
    private let settingsHandler: () -> Void
    private let quitHandler: () -> Void
    private let settingsStore: SettingsStore
    private let menu: NSMenu
    private var searchLyricsItem: NSMenuItem!
    private var ignoreCurrentTrackLyricsItem: NSMenuItem!
    private var revealCurrentLyricsInFinderItem: NSMenuItem!
    private var hideActivitySneaksItem: NSMenuItem!
    private var settingsItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    private var lyricsOffsetItem: NSMenuItem!
    private var offsetView: LyricsOffsetMenuView!
    private var settingsCancellables: Set<AnyCancellable> = []

    public init(
        lyricsActions: StatusItemLyricsActions,
        activitySneakActions: StatusItemActivitySneakActions,
        settingsStore: SettingsStore = .shared,
        settingsHandler: @escaping () -> Void,
        quitHandler: @escaping () -> Void
    ) {
        self.lyricsActions = lyricsActions
        self.activitySneakActions = activitySneakActions
        self.settingsStore = settingsStore
        self.settingsHandler = settingsHandler
        self.quitHandler = quitHandler
        self.menu = NSMenu()
        super.init()

        if let button = statusItem.button {
            button.image = Self.makeNotchedComputerStatusImage()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.title = ""
            button.toolTip = "NotchPilot"
        }

        searchLyricsItem = NSMenuItem(title: "", action: #selector(searchLyrics), keyEquivalent: "")
        menu.addItem(searchLyricsItem)

        ignoreCurrentTrackLyricsItem = NSMenuItem(
            title: "",
            action: #selector(ignoreCurrentTrackLyrics),
            keyEquivalent: ""
        )
        menu.addItem(ignoreCurrentTrackLyricsItem)

        revealCurrentLyricsInFinderItem = NSMenuItem(
            title: "",
            action: #selector(revealCurrentLyricsInFinder),
            keyEquivalent: ""
        )
        menu.addItem(revealCurrentLyricsInFinderItem)

        offsetView = LyricsOffsetMenuView(onChange: { [weak self] value in
            self?.lyricsActions.setOffset(value)
        })
        lyricsOffsetItem = NSMenuItem()
        lyricsOffsetItem.view = offsetView
        menu.addItem(lyricsOffsetItem)

        menu.addItem(.separator())
        let hideActivitySneaksItem = NSMenuItem(
            title: "",
            action: #selector(toggleActivitySneakPreviews),
            keyEquivalent: ""
        )
        hideActivitySneaksItem.setShortcut(for: .toggleHideAllPreviews)
        self.hideActivitySneaksItem = hideActivitySneaksItem
        menu.addItem(hideActivitySneaksItem)

        settingsItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)

        quitItem = NSMenuItem(title: "", action: #selector(quit), keyEquivalent: "q")
        menu.addItem(quitItem)
        menu.items.forEach { $0.target = self }
        menu.delegate = self
        statusItem.menu = menu
        syncLocalizedMenuTitles(language: settingsStore.interfaceLanguage)

        settingsStore.$interfaceLanguage
            .removeDuplicates()
            .sink { [weak self] language in
                self?.syncLocalizedMenuTitles(language: language)
            }
            .store(in: &settingsCancellables)
    }

    @objc private func searchLyrics() {
        lyricsActions.search()
    }

    @objc private func ignoreCurrentTrackLyrics() {
        lyricsActions.ignoreCurrentTrack()
    }

    @objc private func revealCurrentLyricsInFinder() {
        lyricsActions.revealCurrentLyricsInFinder()
    }

    @objc private func toggleActivitySneakPreviews() {
        activitySneakActions.toggle()
        syncActivitySneakPreviewMenuState()
    }

    @objc private func openSettings() {
        settingsHandler()
    }

    @objc private func quit() {
        quitHandler()
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(searchLyrics):
            return lyricsActions.canSearchCurrentTrack()
        case #selector(ignoreCurrentTrackLyrics):
            return lyricsActions.canIgnoreCurrentTrack()
        case #selector(revealCurrentLyricsInFinder):
            return lyricsActions.canRevealCurrentLyricsInFinder()
        default:
            return true
        }
    }

    var menuItemTitlesForTesting: [String] {
        menu.items.map(\.title)
    }

    var menuItemsForTesting: [NSMenuItem] {
        menu.items
    }

    private func syncActivitySneakPreviewMenuState() {
        hideActivitySneaksItem.state = activitySneakActions.isHidden() ? .on : .off
    }

    private func syncLocalizedMenuTitles(language: AppLanguage) {
        searchLyricsItem.title = AppStrings.text(.searchLyricsMenu, language: language)
        ignoreCurrentTrackLyricsItem.title = AppStrings.text(.markLyricsWrongMenu, language: language)
        revealCurrentLyricsInFinderItem.title = AppStrings.text(.revealLyricsCacheMenu, language: language)
        hideActivitySneaksItem.title = AppStrings.text(.hideAllSneaksMenu, language: language)
        settingsItem.title = AppStrings.text(.settingsMenu, language: language)
        quitItem.title = AppStrings.text(.quitNotchPilotMenu, language: language)
        offsetView.syncLocalizedText(language: language)
    }

    private static func makeNotchedComputerStatusImage() -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let displayRect = NSRect(x: 2.5, y: 4.5, width: 17, height: 11)
            let display = NSBezierPath(roundedRect: displayRect, xRadius: 2.8, yRadius: 2.8)
            display.lineWidth = 1.8
            display.stroke()

            let notch = NSBezierPath(
                roundedRect: NSRect(x: 8.0, y: 12.2, width: 6.0, height: 4.2),
                xRadius: 1.5,
                yRadius: 1.5
            )
            notch.fill()

            let base = NSBezierPath()
            base.move(to: NSPoint(x: 7.0, y: 2.5))
            base.line(to: NSPoint(x: 15.0, y: 2.5))
            base.lineWidth = 1.8
            base.lineCapStyle = .round
            base.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }
}

extension StatusItemController: NSMenuDelegate {
    public func menuWillOpen(_ menu: NSMenu) {
        syncActivitySneakPreviewMenuState()
        let enabled = lyricsActions.canAdjustOffset()
        lyricsOffsetItem.isHidden = !enabled
        if enabled {
            offsetView.update(value: lyricsActions.getOffset())
        }
        // While the status menu is open, NSMenu enters tracking mode and
        // buffers global keyboard events. Disable the global shortcut so it
        // does not fire repeatedly when the menu closes.
        KeyboardShortcuts.disable(.toggleHideAllPreviews)
    }

    public func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.enable(.toggleHideAllPreviews)
    }
}

final class LyricsOffsetMenuView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let textField = NSTextField()
    private let stepper = NSStepper()
    private let unitLabel = NSTextField(labelWithString: "ms")
    private var onChange: ((Int) -> Void)?

    init(onChange: @escaping (Int) -> Void) {
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setupViews() {
        label.font = .menuFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        textField.integerValue = 0
        textField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        textField.alignment = .right
        textField.formatter = signedIntegerFormatter()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.target = self
        textField.action = #selector(textFieldChanged)
        addSubview(textField)

        stepper.integerValue = 0
        stepper.minValue = -30000
        stepper.maxValue = 30000
        stepper.increment = 100
        stepper.valueWraps = false
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.target = self
        stepper.action = #selector(stepperChanged)
        addSubview(stepper)

        unitLabel.font = .menuFont(ofSize: 13)
        unitLabel.textColor = .secondaryLabelColor
        unitLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(unitLabel)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            textField.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.widthAnchor.constraint(equalToConstant: 70),

            stepper.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 4),
            stepper.centerYAnchor.constraint(equalTo: centerYAnchor),

            unitLabel.leadingAnchor.constraint(equalTo: stepper.trailingAnchor, constant: 4),
            unitLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func update(value: Int) {
        textField.integerValue = value
        stepper.integerValue = value
    }

    func syncLocalizedText(language: AppLanguage) {
        label.stringValue = AppStrings.text(.lyricsOffsetLabel, language: language)
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        textField.integerValue = sender.integerValue
        onChange?(sender.integerValue)
    }

    @objc private func textFieldChanged(_ sender: NSTextField) {
        let value = sender.integerValue
        stepper.integerValue = value
        onChange?(value)
    }

    private func signedIntegerFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = -30000
        formatter.maximum = 30000
        return formatter
    }
}
