import AppKit

/// Convertino-style ring: during a content drag, tap Shift to show conversion petals around the
/// pointer; drop on one to convert into the shelf. Its modifier monitors exist only between
/// `dragBegan` and `dragEnded`, so it costs nothing at idle.
@MainActor
final class RadialController {
    static let shared = RadialController()

    private var monitors: [Any] = []
    private var tap = ShiftTap()
    private var panel: RingPanel?
    private var urls: [URL] = []

    /// A drag carrying content started (called by DragMonitor).
    func dragBegan(_ pasteboard: NSPasteboard) {
        guard Prefs.shared.shiftRing, monitors.isEmpty else { return }
        urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return }
        tap = ShiftTap()
        let handler: (NSEvent) -> Void = { [weak self] e in MainActor.assumeIsolated { self?.flagsChanged(e) } }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { handler($0); return $0 }) { monitors.append(m) }
    }

    /// The drag ended, dropped anywhere (called by DragMonitor on mouse-up).
    func dragEnded() {
        guard !monitors.isEmpty || panel != nil else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        close()
        urls = []
    }

    private func flagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let others = !flags.intersection([.command, .option, .control]).isEmpty
        guard tap.update(shift: flags.contains(.shift), others: others, at: event.timestamp) else { return }
        if panel != nil { close() } else { open(at: NSEvent.mouseLocation) }
    }

    private func open(at point: CGPoint) {
        let actions = Converter.actions(for: urls, tools: .detect())
        let ring = RingPanel(center: point, actions: actions) { [weak self] choice, dropped in
            self?.perform(choice, dropped)
        }
        ring.orderFrontRegardless()
        panel = ring
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func perform(_ choice: RingPanel.Choice, _ dropped: [URL]) {
        let point = NSEvent.mouseLocation
        close()
        let shelf = ShelfController.shared
        switch choice {
        case .cancel:
            return
        case .shelf:
            shelf.model.add(dropped)
        case .convert(let action):
            shelf.model.run(action, on: dropped)
        }
        shelf.show(at: point)
    }
}

/// Transparent, non-activating panel holding the petals. Only petals accept the drop.
final class RingPanel: NSPanel {
    enum Choice: Equatable {
        case cancel, shelf
        case convert(ConvertAction)
    }

    init(center: CGPoint, actions: [ConvertAction], onDrop: @escaping (Choice, [URL]) -> Void) {
        let choices: [Choice] = actions.map(Choice.convert) + [.shelf]
        let side = RadialLayout.extent(count: choices.count)
        super.init(contentRect: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let root = NSView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        let mid = CGPoint(x: side / 2, y: side / 2)
        let size = RadialLayout.petalSize
        for (choice, offset) in zip(choices, RadialLayout.place(count: choices.count)) {
            let petal = PetalView(choice: choice, onDrop: onDrop)
            petal.frame = CGRect(x: mid.x + offset.x - size / 2, y: mid.y + offset.y - size / 2, width: size, height: size)
            root.addSubview(petal)
        }
        let cancel = PetalView(choice: .cancel, onDrop: onDrop)
        let c: CGFloat = 44
        cancel.frame = CGRect(x: mid.x - c / 2, y: mid.y - c / 2, width: c, height: c)
        root.addSubview(cancel)
        contentView = root
    }
}

/// One round drop target. Highlights while a drag hovers; reads file URLs on drop.
final class PetalView: NSView {
    let choice: RingPanel.Choice
    private let onDrop: (RingPanel.Choice, [URL]) -> Void
    private let label = NSTextField(labelWithString: "")
    private var hovering = false { didSet { updateColors() } }

    init(choice: RingPanel.Choice, onDrop: @escaping (RingPanel.Choice, [URL]) -> Void) {
        self.choice = choice
        self.onDrop = onDrop
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 1
        registerForDraggedTypes([.fileURL])
        switch choice {
        case .cancel: label.stringValue = "✕"
        case .shelf: label.stringValue = "Shelf"
        case .convert(let a): label.stringValue = a.shortTitle
        }
        label.font = .systemFont(ofSize: choice == .cancel ? 15 : 11, weight: .semibold)
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        addSubview(label)
        setAccessibilityLabel(label.stringValue)
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
        let h = label.intrinsicContentSize.height * (label.stringValue.contains(" ") ? 2 : 1)
        label.frame = CGRect(x: 4, y: (bounds.height - h) / 2, width: bounds.width - 8, height: h)
    }

    override func viewDidChangeEffectiveAppearance() { updateColors() }

    private func updateColors() {
        let accent = NSColor.controlAccentColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (hovering ? accent : NSColor.windowBackgroundColor.withAlphaComponent(0.92)).cgColor
            layer?.borderColor = (hovering ? accent : NSColor.separatorColor).cgColor
        }
        label.textColor = hovering ? .white : (choice == .cancel ? .secondaryLabelColor : .labelColor)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hovering = true
        return choice == .cancel ? .generic : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { hovering = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hovering = false
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                          options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        // Hand off after the drop completes, so the drag source isn't kept waiting on a conversion.
        DispatchQueue.main.async { [choice, onDrop] in onDrop(choice, urls) }
        return choice != .cancel
    }
}
