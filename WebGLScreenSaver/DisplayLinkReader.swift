import Cocoa
import SwiftUI

@MainActor
final class DisplayLink {
    let parentView: NSView

    private var displayLink: CADisplayLink?
    private var update: (() -> Void)?

    init(parentView: NSView) {
        self.parentView = parentView
    }

    func start(update: @escaping () -> Void) {
        stop()

        self.update = update

        displayLink = parentView.displayLink(
            target: self,
            selector: #selector(frame)
        )

        displayLink?.add(to: .current, forMode: .default)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        update = nil
    }

    @objc
    private func frame() {
        update?()
    }
}

@MainActor
struct DisplayLinkReader<Content: View>: NSViewRepresentable {
    private let content: (DisplayLink) -> Content

    init(
        @ViewBuilder content: @escaping (DisplayLink) -> Content
    ) {
        self.content = content
    }

    final class Coordinator {
        var displayLink: DisplayLink?
        var hostingView: NSHostingView<Content>?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let parentView = NSView()

        let displayLink = DisplayLink(parentView: parentView)
        let hostingView = NSHostingView(
            rootView: content(displayLink)
        )

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(
                equalTo: parentView.leadingAnchor
            ),
            hostingView.trailingAnchor.constraint(
                equalTo: parentView.trailingAnchor
            ),
            hostingView.topAnchor.constraint(
                equalTo: parentView.topAnchor
            ),
            hostingView.bottomAnchor.constraint(
                equalTo: parentView.bottomAnchor
            ),
        ])

        context.coordinator.displayLink = displayLink
        context.coordinator.hostingView = hostingView

        return parentView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard
            let displayLink = context.coordinator.displayLink,
            let hostingView = context.coordinator.hostingView
        else {
            return
        }

        hostingView.rootView = content(displayLink)
    }

    static func dismantleNSView(
        _ nsView: NSView,
        coordinator: Coordinator
    ) {
        coordinator.displayLink?.stop()
        coordinator.displayLink = nil
        coordinator.hostingView = nil
    }
}
