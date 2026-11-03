public let ONE = 65536
@inline(__always) public func qmul(_ a: Int, _ b: Int) -> Int { (a * b) >> 16 }

public struct Tune: Sendable {
    public static let vBase = 9830
    public static let accel = 328      // 0 -> base in 30 ticks
    public static let decel = 218      // ground slowdown toward lower target
    public static let airDrag = 73     // bleed above base while airborne
    public static let hopV = 19005
    public static let cutV = 8520
    public static let gUp = 874
    public static let gDown = 1129
    public static let terminal = 26214
    public static let plonkV = 32768
    public static let plonkTerm = 37137
    public static let springV = 29491
    public static let coyote = 6
    public static let hopBuffer = 8
    public static let w = 58982
    public static let hStand = 91750
    public static let hTuck = 45875
    public static let corner = 16384
    public static let hazInset = 9830
    public static let tuckGrace = 24          // ticks before drag begins
    public static let tuckDrag = 60293
    public static let rollMul = 73400
    public static let rollTicks = 36
    public static let rollMinFall = 98304
    public static let thudTicks = 5
    public static let thudMul = 45875
    public static let fastBelt = 85197
    public static let fastWire = 81920
    public static let drag = 52429
    public static let bonkTicks = 66          // 1.10 s out of play
    public static let invuln = 75             // 1.25 s
    public static let stuckTicks = 300
    public static let anchorSpacing = 24
}

// Tile legend (ASCII is the authoring format)
//  . empty   # solid   = one-way   - fast wire (one-way x1.25)   > fast belt x1.30   < drag x0.80
//  ^ floor spike   v hanging spike   S spring   H hatch (solid unless plonking)   P parcel   R anchor (overlay)
public struct Input: Sendable {
 public var hop, down: Bool
 public init(hop: Bool = false, down: Bool = false) { self.hop=hop; self.down=down }
}

enum Fail: Int { case none = 0, bonk, bump, band, trap }

public struct Runner: Sendable {
    public init() {}
    public var guardT = 0, immuneT = 0, shakeT = 0, stunT = 0
    public var hazardContact = false
    public var x = 0, y = 0, vx = 0, vy = 0
    public var grounded = false
    public var coyote = 0, hopBuf = 0
    public var prevHop = false, prevDown = false
    public var rising = false, plonking = false
    public var fallTop = 0
    public var tucked = false, tuckTicks = 0, roll = 0, thud = 0
    public var alive = true, bonkTimer = 0, invuln = 0
    public var anchorX = 0, anchorY = 0
    public var statusMul = ONE, statusT = 0
    public var speedMul = ONE, speedT = 0
    public var finished = -1
    public var bonks = 0, bumps = 0, rolls = 0
    public var stuckT = 0, stuckX = 0
    public var bumpFlag = false, bonkFlag = false
    public var noHopT = 0
    public var taxMul = ONE
    public var streakAnchor = -1, streak = 0, mercies = 0
}

@inline(__always) func isSolid(_ t: UInt8, _ plonk: Bool) -> Bool {
    switch t { case 35, 62, 60: return true; case 72: return !plonk; default: return false }
}
@inline(__always) func isTop(_ t: UInt8) -> Bool { t == 61 || t == 45 }

func hazardOn(_ h: Hazard, _ tick: Int) -> Bool { ((tick + h.phase) % h.period) < h.on }

@inline(__always)
public func step(_ r: inout Runner, _ i: Input, _ tick: Int, _ c: CourseData) {
    r.bumpFlag = false; r.bonkFlag = false
    if r.finished >= 0 { return }
    if !r.alive {
        r.bonkTimer -= 1
        if r.bonkTimer <= 0 {
            if r.anchorX == r.streakAnchor { r.streak += 1 } else { r.streakAnchor = r.anchorX; r.streak = 1 }
            if r.streak >= 3 {
                var best = -1, bestD = Int.max
                let ax = r.anchorX >> 16, ay = r.anchorY >> 16
                for (ai, a) in c.anchors.enumerated() where a.x > ax && a.x <= ax + 48 {
                    let d = (a.x - ax) * 4 + abs(a.y - ay) * 8
                    if d < bestD { bestD = d; best = ai }
                }
                if best >= 0 {
                    r.anchorX = (c.anchors[best].x << 16) + ONE / 2; r.anchorY = c.anchors[best].y << 16
                    r.streak = 0; r.streakAnchor = -1; r.mercies += 1
                }
            }
            r.alive = true; r.x = r.anchorX; r.y = r.anchorY; r.vx = 0; r.vy = 0; r.grounded = true
            r.invuln = Tune.invuln; r.plonking = false; r.tucked = false; r.roll = 0; r.thud = 0
            r.statusT = 0; r.statusMul = ONE; r.speedT = 0; r.speedMul = ONE; r.stuckT = 0; r.stuckX = r.x
            r.rising = false; r.hopBuf = 0; r.coyote = 0
            r.guardT = 0; r.immuneT = 0; r.shakeT = 0; r.stunT = 0; r.noHopT = 0; r.hazardContact = false
        }
        r.prevHop = i.hop; r.prevDown = i.down
        return
    }
    if r.invuln > 0 { r.invuln -= 1 }
    if r.statusT > 0 { r.statusT -= 1; if r.statusT == 0 { r.statusMul = ONE } }
    if r.speedT > 0 { r.speedT -= 1; if r.speedT == 0 { r.speedMul = ONE } }
    if r.noHopT > 0 { r.noHopT -= 1 }
    let pressHop = i.hop && !r.prevHop
    let pressDown = i.down && !r.prevDown
    r.prevHop = i.hop; r.prevDown = i.down
    if pressHop { r.hopBuf = Tune.hopBuffer } else if r.hopBuf > 0 { r.hopBuf -= 1 }
    // hop (ignored while tucked under a ceiling: the buffer keeps it alive for the exit)
    let hopCL = (r.x - Tune.w / 2) >> 16, hopCR = (r.x + Tune.w / 2 - 1) >> 16
    var tuckedUnder = false
    if r.tucked {
        let rowA = (r.y + Tune.hTuck) >> 16, rowB = (r.y + Tune.hStand - 1) >> 16
        if rowB >= rowA { for row in rowA...rowB { for col in hopCL...hopCR where isSolid(c.at(col, row), false) { tuckedUnder = true } } }
    }
    if r.hopBuf > 0 && (r.grounded || r.coyote > 0) && r.noHopT == 0 && !tuckedUnder {
        r.vy = Tune.hopV; r.grounded = false; r.coyote = 0; r.hopBuf = 0; r.rising = true
        r.tucked = false; r.tuckTicks = 0; r.fallTop = r.y
    }
    if r.rising && !i.hop && r.vy > Tune.cutV { r.vy = Tune.cutV; r.rising = false }
    // plonk
    if pressDown && !r.grounded && !r.plonking {
        r.plonking = true; r.vy = -Tune.plonkV; r.rising = false
    }
    // tuck
    let colL = (r.x - Tune.w / 2) >> 16, colR = (r.x + Tune.w / 2 - 1) >> 16
    func headBlocked() -> Bool {
        let rowA = (r.y + Tune.hTuck) >> 16, rowB = (r.y + Tune.hStand - 1) >> 16
        if rowB < rowA { return false }
        for row in rowA...rowB { for col in colL...colR where isSolid(c.at(col, row), false) { return true } }
        return false
    }
    if i.down && r.grounded { r.tucked = true } else if r.tucked && !headBlocked() { r.tucked = false }
    if r.tucked && r.grounded { r.tuckTicks += 1 } else if !r.tucked { r.tuckTicks = 0 }
    let hNow = r.tucked ? Tune.hTuck : Tune.hStand
    // horizontal target
    if r.roll > 0 { r.roll -= 1 }
    if r.thud > 0 { r.thud -= 1 }
    var multiplier = qmul(r.speedMul, min(r.statusMul, r.taxMul))
    var target = qmul(Tune.vBase, multiplier)
    if r.grounded {
        let under = c.at(r.x >> 16, (r.y - 1) >> 16)
        switch under {
        case 62: target = qmul(target, Tune.fastBelt)
        case 45: target = qmul(target, Tune.fastWire)
        case 60: target = qmul(target, Tune.drag)
        default: break
        }
        if r.tucked && r.tuckTicks > Tune.tuckGrace { target = qmul(target, Tune.tuckDrag) }
        if r.roll > 0 { target = qmul(target, Tune.rollMul) }
        if r.thud > 0 { target = qmul(target, Tune.thudMul) }
        target = min(qmul(Tune.vBase, 111411), max(qmul(Tune.vBase, 29491), target))
        if r.vx < target { r.vx = min(target, r.vx + Tune.accel) }
        else if r.vx > target { r.vx = max(target, r.vx - Tune.decel) }
    } else {
        multiplier = min(111411, max(29491, multiplier)); target = qmul(Tune.vBase, multiplier)
        if r.vx < target { r.vx = min(target, r.vx + Tune.accel / 2) }
        else if r.vx > target { r.vx = max(target, r.vx - Tune.airDrag) }
    }
    // move X
    if r.vx != 0 {
        let nx = r.x + r.vx
        let colOld = (r.x + Tune.w / 2 - 1) >> 16
        let colNew = (nx + Tune.w / 2 - 1) >> 16
        var blocked = false
        if colNew != colOld {
            let rowLo = r.y >> 16, rowHi = (r.y + hNow - 1) >> 16
            if rowHi >= rowLo {
                for row in rowLo...rowHi where isSolid(c.at(colNew, row), r.plonking) {
                    let top = (row + 1) << 16
                    if row == rowLo && top - r.y <= Tune.corner && r.vy <= 0 {
                        r.y = top; r.vy = 0; r.grounded = true
                    } else { blocked = true }
                }
            }
        }
        if blocked { r.x = (colNew << 16) - Tune.w / 2; r.vx = 0; r.bumpFlag = true; r.bumps += 1; r.roll = 0 }
        else { r.x = nx }
    }
    // gravity + move Y
    let wasGrounded = r.grounded
    if r.plonking {
        r.vy = max(r.vy - Tune.gDown, -Tune.plonkTerm)
    } else {
        r.vy -= (r.vy > 0) ? Tune.gUp : Tune.gDown
        if r.vy < -Tune.terminal { r.vy = -Tune.terminal }
    }
    r.grounded = false
    let cL = (r.x - Tune.w / 2) >> 16, cR = (r.x + Tune.w / 2 - 1) >> 16
    let ny = r.y + r.vy
    if r.vy <= 0 {
        var landed = false
        var row = (r.y - 1) >> 16
        let rowEnd = ny >> 16
        scan: while row >= rowEnd {
            let surf = (row + 1) << 16
            for col in cL...cR {
                let t = c.at(col, row)
                if isSolid(t, r.plonking) || (isTop(t) && r.y >= surf) {
                    r.y = surf; r.vy = 0; landed = true; break scan
                }
            }
            row -= 1
        }
        if landed {
            r.grounded = true
            if r.plonking {
                let fell = r.fallTop - r.y
                if fell >= Tune.rollMinFall && i.down { r.roll = Tune.rollTicks; r.rolls += 1 }
                else { r.thud = Tune.thudTicks }
                r.plonking = false
            }
            r.rising = false
        } else { r.y = ny }
    } else {
        let headOld = (r.y + hNow - 1) >> 16, headNew = (ny + hNow - 1) >> 16
        var hit = false
        if headNew != headOld { for col in cL...cR where isSolid(c.at(col, headNew), r.plonking) { hit = true } }
        if hit { r.y = (headNew << 16) - hNow; r.vy = 0; r.rising = false } else { r.y = ny }
    }
    if r.y > r.fallTop || r.grounded { r.fallTop = r.y }
    if wasGrounded && !r.grounded && r.vy <= 0 { r.coyote = Tune.coyote }
    else if r.coyote > 0 { r.coyote -= 1 }
    if r.grounded { r.coyote = 0 }
    // specials under/inside box
    let boxL = r.x - Tune.w / 2 + Tune.hazInset, boxR = r.x + Tune.w / 2 - Tune.hazInset
    let boxB = r.y + Tune.hazInset / 2, boxT = r.y + hNow - Tune.hazInset
    let rLo = max(0, boxB >> 16), rHi = min(c.h - 1, boxT >> 16)
    if rHi >= rLo {
        for row in rLo...rHi {
            for col in (boxL >> 16)...(boxR >> 16) {
                let t = c.at(col, row)
                if t == 83 && r.vy <= 0 { r.vy = Tune.springV; r.grounded = false; r.rising = false; r.plonking = false; r.fallTop = r.y }
                if r.invuln == 0 {
                    if t == 94 && boxB < (row << 16) + 39322 { r.bonkFlag = true }
                    if t == 118 && boxT > (row << 16) + 26214 { r.bonkFlag = true }
                }
            }
        }
    }
    if r.invuln == 0 {
        for h in c.hazards where hazardOn(h, tick) {
            if boxR > (h.x0 << 16) && boxL < ((h.x1 + 1) << 16) && boxT > h.y0 && boxB < h.y1 { r.bonkFlag = true }
        }
    }
    if r.y < 0 { r.bonkFlag = true }
    // anchors (grounded pass)
    if r.grounded && r.invuln == 0 {
        for a in c.anchors where (a.x << 16) <= r.x && a.x > (r.anchorX >> 16) && abs((a.y << 16) - r.y) <= (2 << 16) {
            r.anchorX = (a.x << 16) + ONE / 2; r.anchorY = a.y << 16
        }
    }
    // A guard absorbs the entire continuous hazard contact, never a pit.
    let touchingHazard = r.bonkFlag && r.y >= 0
    if touchingHazard && (r.hazardContact || r.guardT > 0) {
        if !r.hazardContact { r.guardT = 0 }
        r.bonkFlag = false
    }
    r.hazardContact = touchingHazard
    // anti softlock
    if r.x - r.stuckX >= ONE { r.stuckX = r.x; r.stuckT = 0 } else { r.stuckT += 1; if r.stuckT >= Tune.stuckTicks { r.bonkFlag = true } }
    if r.bonkFlag {
        r.alive = false; r.bonkTimer = Tune.bonkTicks; r.bonks += 1; r.grounded = false
        return
    }
    if r.x >= c.finishX << 16 { r.finished = tick }
}
