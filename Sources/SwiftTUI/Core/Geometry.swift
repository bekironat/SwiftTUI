import Foundation

/// A 2D point in terminal cell coordinates (0-indexed column `x` and row `y`).
public struct Point: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int

    public static let zero = Point(x: 0, y: 0)

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public var description: String {
        "(\(x), \(y))"
    }
}

/// A 2D size in terminal cells (`width` columns by `height` rows).
public struct Size: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public static let zero = Size(width: 0, height: 0)

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public var isEmpty: Bool {
        width <= 0 || height <= 0
    }

    public var area: Int {
        width * height
    }

    public var description: String {
        "\(width)x\(height)"
    }
}

/// Edge insets measured in terminal cells.
public struct EdgeInsets: Equatable, Hashable, Sendable {
    public var top: Int
    public var leading: Int
    public var bottom: Int
    public var trailing: Int

    public static let zero = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

    public init(top: Int = 0, leading: Int = 0, bottom: Int = 0, trailing: Int = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init(all: Int) {
        self.top = all
        self.leading = all
        self.bottom = all
        self.trailing = all
    }

    public init(horizontal: Int = 0, vertical: Int = 0) {
        self.top = vertical
        self.bottom = vertical
        self.leading = horizontal
        self.trailing = horizontal
    }

    public var horizontal: Int { leading + trailing }
    public var vertical: Int { top + bottom }
}

/// Edges of a rectangle.
public struct Edge: Equatable, Hashable, Sendable {
    public struct Set: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let top = Set(rawValue: 1 << 0)
        public static let leading = Set(rawValue: 1 << 1)
        public static let bottom = Set(rawValue: 1 << 2)
        public static let trailing = Set(rawValue: 1 << 3)

        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
        public static let all: Set = [.top, .leading, .bottom, .trailing]
    }
}

/// A rectangular region of terminal cells.
public struct Rect: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public init(origin: Point, size: Size) {
        self.init(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    public var origin: Point {
        get { Point(x: x, y: y) }
        set { x = newValue.x; y = newValue.y }
    }

    public var size: Size {
        get { Size(width: width, height: height) }
        set { width = max(0, newValue.width); height = max(0, newValue.height) }
    }

    public var minX: Int { x }
    public var maxX: Int { x + width }
    public var minY: Int { y }
    public var maxY: Int { y + height }
    public var midX: Int { x + width / 2 }
    public var midY: Int { y + height / 2 }

    public var isEmpty: Bool {
        width <= 0 || height <= 0
    }

    public var area: Int {
        width * height
    }

    public func contains(_ point: Point) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    public func intersection(_ other: Rect) -> Rect {
        let nx = max(minX, other.minX)
        let ny = max(minY, other.minY)
        let nw = min(maxX, other.maxX) - nx
        let nh = min(maxY, other.maxY) - ny
        if nw <= 0 || nh <= 0 {
            return .zero
        }
        return Rect(x: nx, y: ny, width: nw, height: nh)
    }

    public func inset(by insets: EdgeInsets) -> Rect {
        let nx = x + insets.leading
        let ny = y + insets.top
        let nw = max(0, width - insets.horizontal)
        let nh = max(0, height - insets.vertical)
        return Rect(x: nx, y: ny, width: nw, height: nh)
    }

    public func inset(dx: Int, dy: Int) -> Rect {
        inset(by: EdgeInsets(horizontal: dx, vertical: dy))
    }

    /// Splits a rectangle horizontally into `(left, right)` at the given column offset or ratio.
    public func splitHorizontal(firstWidth: Int, spacing: Int = 0) -> (left: Rect, right: Rect) {
        let clampedFirst = max(0, min(width, firstWidth))
        let leftRect = Rect(x: x, y: y, width: clampedFirst, height: height)
        let rightStart = min(maxX, x + clampedFirst + spacing)
        let rightWidth = max(0, maxX - rightStart)
        let rightRect = Rect(x: rightStart, y: y, width: rightWidth, height: height)
        return (leftRect, rightRect)
    }

    /// Splits a rectangle vertically into `(top, bottom)` at the given row offset.
    public func splitVertical(firstHeight: Int, spacing: Int = 0) -> (top: Rect, bottom: Rect) {
        let clampedFirst = max(0, min(height, firstHeight))
        let topRect = Rect(x: x, y: y, width: width, height: clampedFirst)
        let bottomStart = min(maxY, y + clampedFirst + spacing)
        let bottomHeight = max(0, maxY - bottomStart)
        let bottomRect = Rect(x: x, y: bottomStart, width: width, height: bottomHeight)
        return (topRect, bottomRect)
    }

    public var description: String {
        "Rect(\(x), \(y), \(width)x\(height))"
    }
}

/// Horizontal alignment options matching SwiftUI.
public enum HorizontalAlignment: Equatable, Hashable, Sendable {
    case leading
    case center
    case trailing
}

/// Vertical alignment options matching SwiftUI.
public enum VerticalAlignment: Equatable, Hashable, Sendable {
    case top
    case center
    case bottom
}

/// 2D alignment combining horizontal and vertical alignment.
public struct Alignment: Equatable, Hashable, Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment

    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}

/// Layout or scroll axis.
public enum Axis: Equatable, Hashable, Sendable {
    case horizontal
    case vertical

    public struct Set: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let horizontal = Set(rawValue: 1 << 0)
        public static let vertical = Set(rawValue: 1 << 1)
        public static let all: Set = [.horizontal, .vertical]
    }
}

/// Size proposed by a parent layout to a child view during layout negotiation.
/// `nil` indicates an unspecified dimension (asking for the child's ideal size),
/// while `Int.max` represents `.infinity` (expanding).
public struct ProposedViewSize: Equatable, Hashable, Sendable {
    public static let infinityDimension: Int = 100_000

    public var width: Int?
    public var height: Int?

    public static let zero = ProposedViewSize(width: 0, height: 0)
    public static let unspecified = ProposedViewSize(width: nil, height: nil)
    public static let infinity = ProposedViewSize(width: infinityDimension, height: infinityDimension)

    public init(width: Int?, height: Int?) {
        self.width = width
        self.height = height
    }

    public init(_ size: Size) {
        self.width = size.width
        self.height = size.height
    }

    public func replacingUnspecifiedDimensions(by fallback: Size = Size(width: 10, height: 1)) -> Size {
        Size(
            width: width ?? fallback.width,
            height: height ?? fallback.height
        )
    }
}
