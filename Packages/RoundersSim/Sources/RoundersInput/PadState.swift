import RoundersSim
/// Plain snapshot of the only inputs the simulator bridge forwards, plus Options for real hardware.
public struct PadState: Sendable, Equatable {
    public var a = false, b = false, x = false, y = false
    public var l1 = false, r1 = false, l2: Float = 0, r2: Float = 0
    public var dpadUp = false, dpadDown = false, menu = false
    public var stickY: Float = 0
    public init() {}
}
public func mapPad(_ p: PadState) -> InputFrame {
    var b: UInt8 = 0
    if p.a { b |= InputFrame.hop }
    if p.b || p.dpadDown || p.stickY < -0.5 { b |= InputFrame.down }
    if p.l1 || p.l2 > 0.3 { b |= InputFrame.handL }
    if p.r1 || p.r2 > 0.3 { b |= InputFrame.handR }
    if p.menu || p.y { b |= 16 }
    return InputFrame(bits: b)
}
