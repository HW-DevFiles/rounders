public struct InputFrame: Sendable, Equatable {
    public var bits: UInt8
    public init(bits: UInt8 = 0) { self.bits = bits }
    public static let hop: UInt8 = 1 << 0
    public static let down: UInt8 = 1 << 1
    public static let handL: UInt8 = 1 << 2
    public static let handR: UInt8 = 1 << 3
    public func has(_ m: UInt8) -> Bool { bits & m != 0 }
    public var names: String {
        var n: [String] = []
        if has(Self.hop) { n.append("hop") }
        if has(Self.down) { n.append("down") }
        if has(Self.handL) { n.append("handL") }
        if has(Self.handR) { n.append("handR") }
        return n.joined(separator: "+")
    }
}
