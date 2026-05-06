import CoreGraphics

@MainActor
struct NotchLayoutMetrics {
    static let closedInteractionHorizontalPadding: CGFloat = 0
    static let closedInteractionBottomPadding: CGFloat = 0

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
            let preview = plugins
                .first(where: { $0.id == session.currentSneakPeek?.pluginID })
                .flatMap { $0.preview(context: context) }
            let previewWidth = preview?.width ?? session.geometry.compactSize.width
            let previewHeight = preview?.height ?? session.geometry.compactSize.height

            return CGSize(
                width: max(session.geometry.compactSize.width, previewWidth),
                height: max(session.geometry.compactSize.height, previewHeight)
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
