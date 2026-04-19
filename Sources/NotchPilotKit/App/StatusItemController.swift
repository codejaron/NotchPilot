import AppKit

@MainActor
public final class StatusItemController: NSObject, NSMenuItemValidation {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    private let searchLyricsHandler: () -> Void
    private let ignoreCurrentTrackLyricsHandler: () -> Void
    private let revealCurrentLyricsInFinderHandler: () -> Void
    private let settingsHandler: () -> Void
    private let quitHandler: () -> Void
    private let canSearchCurrentTrackLyrics: () -> Bool
    private let canIgnoreCurrentTrackLyrics: () -> Bool
    private let canRevealCurrentLyricsInFinder: () -> Bool
    private let canAdjustLyricsOffset: () -> Bool
    private let getLyricsOffset: () -> Int
    private let setLyricsOffset: (Int) -> Void
    private let isActivitySneakPreviewsHidden: () -> Bool
    private let toggleActivitySneakPreviewsHandler: () -> Void
    private let menu: NSMenu
    private var hideActivitySneaksItem: NSMenuItem!
    private var lyricsOffsetItem: NSMenuItem!
    private var offsetView: LyricsOffsetMenuView!

    public init(
        searchLyricsHandler: @escaping () -> Void,
        ignoreCurrentTrackLyricsHandler: @escaping () -> Void,
        revealCurrentLyricsInFinderHandler: @escaping () -> Void,
        canSearchCurrentTrackLyrics: @escaping () -> Bool,
        canIgnoreCurrentTrackLyrics: @escaping () -> Bool,
        canRevealCurrentLyricsInFinder: @escaping () -> Bool,
        canAdjustLyricsOffset: @escaping () -> Bool,
        getLyricsOffset: @escaping () -> Int,
        setLyricsOffset: @escaping (Int) -> Void,
        isActivitySneakPreviewsHidden: @escaping () -> Bool,
        toggleActivitySneakPreviewsHandler: @escaping () -> Void,
        settingsHandler: @escaping () -> Void,
        quitHandler: @escaping () -> Void
    ) {
        self.searchLyricsHandler = searchLyricsHandler
        self.ignoreCurrentTrackLyricsHandler = ignoreCurrentTrackLyricsHandler
        self.revealCurrentLyricsInFinderHandler = revealCurrentLyricsInFinderHandler
        self.canSearchCurrentTrackLyrics = canSearchCurrentTrackLyrics
        self.canIgnoreCurrentTrackLyrics = canIgnoreCurrentTrackLyrics
        self.canRevealCurrentLyricsInFinder = canRevealCurrentLyricsInFinder
        self.canAdjustLyricsOffset = canAdjustLyricsOffset
        self.getLyricsOffset = getLyricsOffset
        self.setLyricsOffset = setLyricsOffset
        self.isActivitySneakPreviewsHidden = isActivitySneakPreviewsHidden
        self.toggleActivitySneakPreviewsHandler = toggleActivitySneakPreviewsHandler
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

        menu.addItem(NSMenuItem(title: "Search Lyrics…", action: #selector(searchLyrics), keyEquivalent: ""))
        menu.addItem(
            NSMenuItem(
                title: "Mark Current Lyrics as Wrong",
                action: #selector(ignoreCurrentTrackLyrics),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Reveal Lyrics Cache in Finder",
                action: #selector(revealCurrentLyricsInFinder),
                keyEquivalent: ""
            )
        )

        offsetView = LyricsOffsetMenuView(onChange: { [weak self] value in
            self?.setLyricsOffset(value)
        })
        lyricsOffsetItem = NSMenuItem()
        lyricsOffsetItem.view = offsetView
        menu.addItem(lyricsOffsetItem)

        menu.addItem(.separator())
        let hideActivitySneaksItem = NSMenuItem(
            title: "Hide All Sneaks",
            action: #selector(toggleActivitySneakPreviews),
            keyEquivalent: "s"
        )
        hideActivitySneaksItem.keyEquivalentModifierMask = [.command, .shift]
        self.hideActivitySneaksItem = hideActivitySneaksItem
        menu.addItem(hideActivitySneaksItem)
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit NotchPilot", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func searchLyrics() {
        searchLyricsHandler()
    }

    @objc private func ignoreCurrentTrackLyrics() {
        ignoreCurrentTrackLyricsHandler()
    }

    @objc private func revealCurrentLyricsInFinder() {
        revealCurrentLyricsInFinderHandler()
    }

    @objc private func toggleActivitySneakPreviews() {
        toggleActivitySneakPreviewsHandler()
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
            return canSearchCurrentTrackLyrics()
        case #selector(ignoreCurrentTrackLyrics):
            return canIgnoreCurrentTrackLyrics()
        case #selector(revealCurrentLyricsInFinder):
            return canRevealCurrentLyricsInFinder()
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
        hideActivitySneaksItem.state = isActivitySneakPreviewsHidden() ? .on : .off
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
        let enabled = canAdjustLyricsOffset()
        lyricsOffsetItem.isHidden = !enabled
        if enabled {
            offsetView.update(value: getLyricsOffset())
        }
    }
}

final class LyricsOffsetMenuView: NSView {
    private let label = NSTextField(labelWithString: "歌词偏移:")
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
