import Foundation

// MARK: - Animation & Timing Curves

/// Defines timing curves and duration for interpolating state changes and layout transitions.
/// Mirrors SwiftUI's `Animation` API.
public struct Animation: Sendable, Equatable {
    public enum Curve: Sendable, Equatable {
        case linear
        case easeIn
        case easeOut
        case easeInOut
        case spring(response: Double, dampingRatio: Double)
    }

    public var curve: Curve
    public var duration: Double
    public var delay: Double
    public var repeatCount: Int?
    public var autoreverses: Bool

    public init(
        curve: Curve,
        duration: Double = 0.35,
        delay: Double = 0.0,
        repeatCount: Int? = nil,
        autoreverses: Bool = false
    ) {
        self.curve = curve
        self.duration = max(0.001, duration)
        self.delay = max(0.0, delay)
        self.repeatCount = repeatCount
        self.autoreverses = autoreverses
    }

    public static let `default` = Animation(curve: .easeInOut, duration: 0.35)
    public static func linear(duration: Double = 0.35) -> Animation { Animation(curve: .linear, duration: duration) }
    public static func easeIn(duration: Double = 0.35) -> Animation { Animation(curve: .easeIn, duration: duration) }
    public static func easeOut(duration: Double = 0.35) -> Animation { Animation(curve: .easeOut, duration: duration) }
    public static func easeInOut(duration: Double = 0.35) -> Animation { Animation(curve: .easeInOut, duration: duration) }
    public static func spring(response: Double = 0.5, dampingRatio: Double = 0.7) -> Animation {
        Animation(curve: .spring(response: response, dampingRatio: dampingRatio), duration: response)
    }
    public static func bouncy(duration: Double = 0.5, extraBounce: Double = 0.2) -> Animation {
        let damping = max(0.2, 0.7 - extraBounce)
        return Animation(curve: .spring(response: duration, dampingRatio: damping), duration: duration)
    }

    public func delay(_ seconds: Double) -> Animation {
        var copy = self
        copy.delay = seconds
        return copy
    }

    public func speed(_ factor: Double) -> Animation {
        var copy = self
        if factor > 0 {
            copy.duration /= factor
        }
        return copy
    }

    public func repeatCount(_ count: Int, autoreverses: Bool = false) -> Animation {
        var copy = self
        copy.repeatCount = count
        copy.autoreverses = autoreverses
        return copy
    }

    public func repeatForever(autoreverses: Bool = true) -> Animation {
        var copy = self
        copy.repeatCount = Int.max
        copy.autoreverses = autoreverses
        return copy
    }

    /// Evaluates the normalized progress `t` in `[0.0, 1.0]` through the timing curve.
    public func evaluate(progress: Double) -> Double {
        let t = max(0.0, min(1.0, progress))
        switch curve {
        case .linear:
            return t
        case .easeIn:
            return t * t * t
        case .easeOut:
            let inv = 1.0 - t
            return 1.0 - inv * inv * inv
        case .easeInOut:
            if t < 0.5 {
                return 4.0 * t * t * t
            } else {
                let f = ((2.0 * t) - 2.0)
                return 0.5 * f * f * f + 1.0
            }
        case .spring(let response, let dampingRatio):
            let omega = (2.0 * Double.pi) / max(0.001, response)
            let beta = dampingRatio * omega
            let dampedOmega = omega * sqrt(max(0.0, 1.0 - dampingRatio * dampingRatio))
            if dampedOmega == 0 {
                return 1.0 - exp(-beta * t)
            }
            let envelope = exp(-beta * t * response)
            let oscillation = cos(dampedOmega * t * response) + (beta / dampedOmega) * sin(dampedOmega * t * response)
            return 1.0 - envelope * oscillation
        }
    }
}

// MARK: - Vector Arithmetic & Animatable Protocol

/// Protocol for values that can be smoothly interpolated during animations.
public protocol VectorArithmetic: Equatable {
    static var zero: Self { get }
    static func + (lhs: Self, rhs: Self) -> Self
    static func - (lhs: Self, rhs: Self) -> Self
    mutating func scale(by factor: Double)
}

extension Double: VectorArithmetic {
    public mutating func scale(by factor: Double) { self *= factor }
}

extension Float: VectorArithmetic {
    public mutating func scale(by factor: Double) { self = Float(Double(self) * factor) }
}

extension Int: VectorArithmetic {
    public mutating func scale(by factor: Double) { self = Int((Double(self) * factor).rounded()) }
}

extension Point: VectorArithmetic {
    public static func + (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
    public static func - (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
    public mutating func scale(by factor: Double) {
        x = Int((Double(x) * factor).rounded())
        y = Int((Double(y) * factor).rounded())
    }
}

extension Size: VectorArithmetic {
    public static func + (lhs: Size, rhs: Size) -> Size {
        Size(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
    public static func - (lhs: Size, rhs: Size) -> Size {
        Size(width: lhs.width - rhs.width, height: lhs.height - rhs.height)
    }
    public mutating func scale(by factor: Double) {
        width = Int((Double(width) * factor).rounded())
        height = Int((Double(height) * factor).rounded())
    }
}

/// Linear interpolation helper for any `VectorArithmetic` type.
public func lerp<T: VectorArithmetic>(from start: T, to end: T, progress: Double) -> T {
    var delta = end - start
    delta.scale(by: progress)
    return start + delta
}

// MARK: - Color Interpolation (24-bit TrueColor Lerp)

extension Color {
    /// 24-bit RGB components.
    public var rgbComponents: (r: UInt8, g: UInt8, b: UInt8) {
        switch self {
        case .default, .white, .brightWhite: return (255, 255, 255)
        case .black: return (0, 0, 0)
        case .brightBlack: return (100, 100, 100)
        case .red: return (205, 49, 49)
        case .brightRed: return (241, 76, 76)
        case .green: return (13, 188, 121)
        case .brightGreen: return (35, 209, 139)
        case .yellow: return (229, 229, 16)
        case .brightYellow: return (245, 245, 67)
        case .blue: return (36, 114, 200)
        case .brightBlue: return (59, 142, 234)
        case .magenta: return (188, 63, 188)
        case .brightMagenta: return (214, 112, 214)
        case .cyan: return (17, 168, 205)
        case .brightCyan: return (41, 184, 219)
        case .indexed(let idx): return (idx, idx, idx)
        case .rgb(let r, let g, let b): return (r, g, b)
        }
    }

    /// Linearly interpolates from `self` to `other` across TrueColor 24-bit RGB space.
    public func interpolated(to other: Color, progress: Double) -> Color {
        let t = max(0.0, min(1.0, progress))
        let c1 = self.rgbComponents
        let c2 = other.rgbComponents
        let r = UInt8(max(0, min(255, Int((Double(c1.r) + Double(Int(c2.r) - Int(c1.r)) * t).rounded()))))
        let g = UInt8(max(0, min(255, Int((Double(c1.g) + Double(Int(c2.g) - Int(c1.g)) * t).rounded()))))
        let b = UInt8(max(0, min(255, Int((Double(c1.b) + Double(Int(c2.b) - Int(c1.b)) * t).rounded()))))
        return .rgb(r, g, b)
    }
}

// MARK: - Animation Driver & RunLoop Integration

/// Central engine that ticks active animations forward in time at up to 60fps.
@MainActor
public final class AnimationDriver {
    public static let shared = AnimationDriver()

    public struct ActiveAnimation {
        public let id: AnyHashable
        public let startTime: TimeInterval
        public let duration: Double
        public let delay: Double
        public let animation: Animation
        public let update: (Double) -> Void
        public let completion: (() -> Void)?
    }

    private var activeAnimations: [AnyHashable: ActiveAnimation] = [:]

    public var hasActiveAnimations: Bool {
        !activeAnimations.isEmpty
    }

    public func addAnimation(
        id: AnyHashable = UUID(),
        animation: Animation,
        update: @escaping (Double) -> Void,
        completion: (() -> Void)? = nil
    ) {
        let active = ActiveAnimation(
            id: id,
            startTime: Date().timeIntervalSinceReferenceDate,
            duration: animation.duration,
            delay: animation.delay,
            animation: animation,
            update: update,
            completion: completion
        )
        activeAnimations[id] = active
        update(animation.evaluate(progress: 0.0))
    }

    public func removeAnimation(id: AnyHashable) {
        activeAnimations.removeValue(forKey: id)
    }

    public func cancelAll() {
        activeAnimations.removeAll()
    }

    public func tick(now: TimeInterval = Date().timeIntervalSinceReferenceDate, store: StateStore? = nil) {
        guard !activeAnimations.isEmpty else { return }

        var completedIDs: [AnyHashable] = []

        for (id, anim) in activeAnimations {
            let elapsed = now - anim.startTime
            if elapsed < anim.delay {
                continue
            }

            let effectiveElapsed = elapsed - anim.delay
            if anim.duration <= 0.0001 || effectiveElapsed >= anim.duration {
                let evaluated = anim.animation.evaluate(progress: 1.0)
                anim.update(evaluated)
                anim.completion?()
                completedIDs.append(id)
            } else {
                let rawProgress = effectiveElapsed / anim.duration
                let evaluated = anim.animation.evaluate(progress: rawProgress)
                anim.update(evaluated)
            }
        }

        for id in completedIDs {
            activeAnimations.removeValue(forKey: id)
        }

        store?.markDirty()
    }
}

// MARK: - withAnimation Global Function

public struct AnimationContext {
    nonisolated(unsafe) internal static var currentAnimation: Animation? = nil
}

/// Executes a state-modifying closure with an explicit `Animation`.
@MainActor
public func withAnimation<Result>(
    _ animation: Animation = .default,
    _ body: () throws -> Result
) rethrows -> Result {
    let prev = AnimationContext.currentAnimation
    AnimationContext.currentAnimation = animation
    defer { AnimationContext.currentAnimation = prev }
    return try body()
}

// MARK: - Animatable Value Wrapper

/// A reactive animatable state wrapper that smoothly interpolates between values when updated.
@MainActor
public final class AnimatableValue<T: VectorArithmetic> {
    public private(set) var value: T
    public private(set) var targetValue: T
    private var startValue: T
    private let animationID = UUID()

    public init(_ initialValue: T) {
        self.value = initialValue
        self.startValue = initialValue
        self.targetValue = initialValue
    }

    public func setTarget(_ newTarget: T, animation: Animation? = nil, onUpdate: (() -> Void)? = nil) {
        let effectiveAnimation = animation ?? AnimationContext.currentAnimation ?? .default
        self.startValue = self.value
        self.targetValue = newTarget
        if startValue == newTarget { return }

        let start = self.startValue
        let target = self.targetValue

        AnimationDriver.shared.addAnimation(id: animationID, animation: effectiveAnimation, update: { [weak self] progress in
            guard let self else { return }
            self.value = lerp(from: start, to: target, progress: progress)
            onUpdate?()
        })
    }
}

// MARK: - TimelineView (Continuous Animation Pacing)

public struct TimelineSchedule: Sendable {
    public var interval: TimeInterval

    public init(interval: TimeInterval) {
        self.interval = max(0.001, interval)
    }

    public static func periodic(from startDate: Date = Date(), by interval: TimeInterval) -> TimelineSchedule {
        TimelineSchedule(interval: interval)
    }

    public static let animation = TimelineSchedule(interval: 1.0 / 30.0)
    public static let halfSecond = TimelineSchedule(interval: 0.5)
    public static let second = TimelineSchedule(interval: 1.0)
}

public struct TimelineViewContext: Sendable {
    public let date: Date
    public let frame: Int
}

/// A container view that updates its content on a scheduled timeline (30fps/60fps animations, clocks, loaders).
public struct TimelineView<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    public let schedule: TimelineSchedule
    public let content: (TimelineViewContext) -> Content

    public init(
        _ schedule: TimelineSchedule = .animation,
        @ViewBuilder content: @escaping (TimelineViewContext) -> Content
    ) {
        self.schedule = schedule
        self.content = content
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let store = context.store
        let path = context.path
        let frameKey = "\(path).TimelineFrame"
        let currentFrame: Int = store.value(forKey: frameKey, default: 0)

        let schedInterval = schedule.interval
        let animID = AnyHashable(frameKey)

        // Ensure an active periodic driver is ticking
        if !AnimationDriver.shared.hasActiveAnimations {
            AnimationDriver.shared.addAnimation(
                id: animID,
                animation: Animation.linear(duration: schedInterval).repeatForever(autoreverses: false),
                update: { _ in
                    let f: Int = store.value(forKey: frameKey, default: 0)
                    store.setValue(f + 1, forKey: frameKey)
                }
            )
        }

        let ctx = TimelineViewContext(date: Date(), frame: currentFrame)
        let child = content(ctx)
        return resolveView(child, context: context.appending("Content"))
    }
}

// MARK: - Transitions (AnyTransition)

/// Transition effects for inserting or removing views from containers.
public enum AnyTransition: Sendable, Equatable {
    case identity
    case opacity
    case slide
    case move(edge: Edge.Set)
    case scale

    public static let moveTop = AnyTransition.move(edge: .top)
    public static let moveBottom = AnyTransition.move(edge: .bottom)
    public static let moveLeading = AnyTransition.move(edge: .leading)
    public static let moveTrailing = AnyTransition.move(edge: .trailing)
}

// MARK: - Animated View Modifiers

public struct _AnimatedOffsetModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let x: Int
    public let y: Int

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let children = resolveView(content, context: context.appending("Offset"))
        let offX = x
        let offY = y
        return children.map { child in
            RenderNode(
                id: "\(child.id).offset",
                measure: child.sizeThatFits,
                render: { rect, buffer, interactions in
                    let shifted = Rect(x: rect.minX + offX, y: rect.minY + offY, width: rect.width, height: rect.height)
                    child.render(in: shifted, buffer: &buffer, interactions: interactions)
                }
            )
        }
    }
}

extension View {
    /// Offsets the view by an animated or discrete integer number of terminal columns and rows.
    public func offset(x: Int = 0, y: Int = 0) -> some View {
        _AnimatedOffsetModifier(content: self, x: x, y: y)
    }

    /// Attaches an `AnyTransition` to this view.
    public func transition(_ transition: AnyTransition) -> some View {
        self
    }
}
