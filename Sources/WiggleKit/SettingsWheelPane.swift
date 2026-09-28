import AppKit
import SwiftUI

@MainActor
private final class SlotHitTarget: NSButton {
    var onHover: ((Bool) -> Void)?
    /// Returns whether a drag started. Until one does, the release counts
    /// as a click.
    var onDragStart: ((NSEvent) -> Bool)?
    private var hoverArea: NSTrackingArea?

    /// `NSButton` tracks a press in its own loop, which never reports a
    /// drag.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return super.mouseDown(with: event) }
        let start = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                sendAction(action, to: target)
                return
            }
            let location = next.locationInWindow
            if hypot(location.x - start.x, location.y - start.y) >= 4, onDragStart?(event) == true { return }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// The one drop target for a slot dragged across the wheel. AppKit walks up
/// from the view under the pointer to the first view registered for the
/// drag's type, so a drag over any hit target, or between them, lands here.
@MainActor
private final class WheelDropView: NSView {
    static let slotType = NSPasteboard.PasteboardType("net.at6.wiggle.slot")

    var slotAt: ((NSPoint) -> SlotID?)?
    var onTargetChanged: ((SlotID?) -> Void)?
    var onDrop: ((SlotID, SlotID) -> Void)?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([Self.slotType])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let target = destination(of: sender)
        onTargetChanged?(target)
        return target == nil ? [] : .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onTargetChanged?(nil) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let source = source(of: sender), let target = destination(of: sender) else { return false }
        onDrop?(source, target)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) { onTargetChanged?(nil) }

    private func source(of info: NSDraggingInfo) -> SlotID? {
        info.draggingPasteboard.string(forType: Self.slotType).flatMap(Int.init).flatMap(SlotID.init(index:))
    }

    /// `nil` over the slot the drag came from, so a slot dropped back onto
    /// itself slides home instead of counting as a move.
    private func destination(of info: NSDraggingInfo) -> SlotID? {
        guard let source = source(of: info), let slot = slotAt?(info.draggingLocation), slot != source
        else { return nil }
        return slot
    }
}

/// The `Actions` page: the overlay's wheel, made clickable. Clicking a slot
/// opens its `SlotEditorSheet`, dragging a slot moves it. Built once, so its
/// AppKit state lives outside SwiftUI's view lifecycle.
@MainActor
final class WheelPaneViewController: NSViewController {

    private static let side = Config.panelSide(showsOuterRing: true)
    private static let padding: CGFloat = 24
    private static let hintHeight: CGFloat = 20

    static var paneSize: NSSize {
        NSSize(width: side + padding * 2, height: padding + side + 4 + hintHeight + padding)
    }

    private let store: SlotStore
    private let wheel = CircularOverlayView(
        frame: NSRect(x: 0, y: 0, width: WheelPaneViewController.side, height: WheelPaneViewController.side))

    /// `beginSheet` retains the sheet's window, not the object driving it.
    private var activeSheet: SlotEditorSheet?

    init(store: SlotStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = makePane()
    }

    func refresh() {
        wheel.slots = store.slots
    }

    private func makePane() -> NSView {
        let padding = Self.padding
        let side = Self.side

        let pane = WheelDropView(frame: NSRect(origin: .zero, size: Self.paneSize))
        pane.wantsLayer = true
        // The wheel draws for a dark backdrop in either system appearance.
        pane.appearance = NSAppearance(named: .darkAqua)
        pane.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        pane.layer?.cornerRadius = 18
        pane.slotAt = { [weak self] point in
            guard let wheel = self?.wheel else { return nil }
            return wheel.slotID(at: wheel.convert(point, from: nil))
        }
        pane.onTargetChanged = { [weak self] slot in self?.wheel.hovered = slot }
        pane.onDrop = { [weak self] source, destination in
            self?.store.swap(source, with: destination)
            self?.refresh()
        }

        wheel.frame = NSRect(x: padding, y: padding, width: side, height: side)
        pane.addSubview(wheel)
        for id in SlotID.all { pane.addSubview(makeHitTarget(id: id)) }

        let hint = NSTextField(labelWithString: "Click a slot to assign it, drag it to move it")
        hint.alignment = .center
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: padding, y: wheel.frame.maxY + 4, width: side, height: Self.hintHeight)
        pane.addSubview(hint)

        return pane
    }

    private func makeHitTarget(id: SlotID) -> SlotHitTarget {
        let target = SlotHitTarget(title: "", target: self, action: #selector(slotTapped(_:)))
        target.tag = id.index
        target.isBordered = false
        target.setAccessibilityTitle(id.label)
        target.onHover = { [weak self] hovering in self?.wheel.hovered = hovering ? id : nil }
        target.onDragStart = { [weak self, unowned target] event in
            self?.beginDrag(from: id, hitTarget: target, event: event) ?? false
        }

        let center = wheel.convert(SlotLayout.labelCenter(for: id, side: wheel.bounds.width), to: wheel.superview)
        let side = SlotLayout.iconBoxSide(for: id)
        target.frame = NSRect(center: center, size: NSSize(width: side, height: side))
        return target
    }

    private func beginDrag(from id: SlotID, hitTarget: SlotHitTarget, event: NSEvent) -> Bool {
        guard store[id] != nil, let pane = hitTarget.superview else { return false }
        wheel.hovered = nil
        let rectInWheel = wheel.convert(hitTarget.frame, from: pane)
        let image = NSImage(size: rectInWheel.size)
        if let rep = wheel.bitmapImageRepForCachingDisplay(in: rectInWheel) {
            wheel.cacheDisplay(in: rectInWheel, to: rep)
            image.addRepresentation(rep)
        }

        let item = NSPasteboardItem()
        item.setString(String(id.index), forType: WheelDropView.slotType)
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        dragItem.setDraggingFrame(hitTarget.bounds, contents: image)
        let session = hitTarget.beginDraggingSession(with: [dragItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        return true
    }

    @objc private func slotTapped(_ sender: NSButton) {
        presentEditor(for: SlotID.all[sender.tag])
    }

    private func presentEditor(for id: SlotID) {
        guard let window = view.window else { return }
        let sheet = SlotEditorSheet(label: id.label, slot: store.slots[id])
        activeSheet = sheet
        sheet.onSave = { [weak self] slot in self?.store.assign(slot, to: id) }
        sheet.onClear = { [weak self] in self?.store.assign(nil, to: id) }
        sheet.present(on: window) { [weak self] in
            self?.activeSheet = nil
            self?.refresh()
        }
    }
}

extension WheelPaneViewController: NSDraggingSource {
    /// Dropped outside the wheel, a slot slides home.
    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        wheel.hovered = nil
    }
}

struct WheelPaneRepresentable: NSViewControllerRepresentable {
    let viewController: WheelPaneViewController

    func makeNSViewController(context: Context) -> WheelPaneViewController { viewController }
    func updateNSViewController(_ nsViewController: WheelPaneViewController, context: Context) {}
}
