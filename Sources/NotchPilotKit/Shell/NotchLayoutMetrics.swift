import CoreGraphics

@MainActor
struct NotchLayoutMetrics {
    static let closedInteractionHorizontalPadding: CGFloat = 30
    static let closedInteractionBottomPadding: CGFloat = 10

    let displaySize: CGSize
    let interactionSize: CGSize

    static func resolve(session: ScreenSessionModel, plugins: [any NotchPlugin]) -> NotchLayoutMetrics {
        let context = NotchContext(
            screenID: session.id,
            notchState: session.notchState,
            notchGeometry: session.geometry,
            isPrimaryScreen: session.descriptor.isPrimary
        )
        let displaySize = preferredDisplaySize(session: session, plugins: plugins, context: context)
        let interactionSize = preferredInteractionSize(for: displaySize, notchState: session.notchState)

        return NotchLayoutMetrics(displaySize: displaySize, interactionSize: interactionSize)
    }

    private static func preferredDisplaySize(
        session: ScreenSessionModel,
        plugins: [any NotchPlugin],
        context: NotchContext
    ) -> CGSize {
        switch session.notchState {
        case .open:
            return session.geometry.expandedSize
        case .idleClosed:
            return session.geometry.compactSize
        case .previewClosed:
            let previewWidth = plugins
                .first(where: { $0.id == session.currentSneakPeek?.pluginID })
                .flatMap { $0.preview(context: context)?.width }
                ?? session.geometry.compactSize.width

            return CGSize(
                width: max(session.geometry.compactSize.width, previewWidth),
                height: session.geometry.compactSize.height
            )
        }
    }

    private static func preferredInteractionSize(for displaySize: CGSize, notchState: NotchState) -> CGSize {
        guard notchState != .open else {
            return displaySize
        }

        return CGSize(
            width: displaySize.width + (closedInteractionHorizontalPadding * 2),
            height: displaySize.height + closedInteractionBottomPadding
        )
    }
}
