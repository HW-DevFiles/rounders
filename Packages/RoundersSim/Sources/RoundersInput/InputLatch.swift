import RoundersSim

/// Held movement plus edges that survive render frames which execute no ticks.
/// Hands fire once per press; left has priority if both edges arrive together.
public struct InputLatch {
    public private(set) var held: UInt8 = 0
    public private(set) var pending: UInt8 = 0
    private var suppressed: UInt8 = 0
    public init() {}
    public mutating func sample(_ bits: UInt8, capturedEdges: UInt8 = 0) {
        suppressed &= bits
        let active=bits & ~suppressed
        pending |= ((active & ~held) | (capturedEdges & ~suppressed)) & 15
        held=active
    }
    public mutating func consume() -> InputFrame {
        let b=(held & 3) | pending
        pending=0
        return InputFrame(bits:b)
    }
    /// A transition requires release of currently held controls before reuse.
    public mutating func reset(suppressing bits: UInt8 = 0) { held=0; pending=0; suppressed=bits }
}

/// Bounded wall-clock debt. Overload slows game time, never skips a simulation step.
public struct TickClock {
    private var last: Double? = nil
    private var debt: Double = 0
    public init() {}
    public mutating func reset() { last=nil; debt=0 }
    public mutating func advance(_ now: Double, running: Bool) -> Int {
        guard running else { last=now; debt=0; return 0 }
        guard let before=last else { last=now; return 0 }
        last=now
        debt=min(5.0/60.0, debt+max(0,min(now-before,0.1)))
        let ticks=min(5,Int((debt+0.000000001)*60))
        debt=max(0,debt-Double(ticks)/60)
        return ticks
    }
    public var alpha: Double { min(1,max(0,debt*60)) }
}
