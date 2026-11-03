// Probe-based bot: forward-simulate the real step function, act at the last safe moment minus a tier margin.
public struct PCG: Sendable { // PCG32, integer only
    var state: UInt64; var inc: UInt64
    init(seed: UInt64, seq: UInt64) { state = 0; inc = (seq << 1) | 1; _ = next(); state &+= seed; _ = next() }
    mutating func next() -> UInt32 {
        let old = state
        state = old &* 6364136223846793005 &+ inc
        let xs = UInt32(truncatingIfNeeded: ((old >> 18) ^ old) >> 27)
        let rot = UInt32(truncatingIfNeeded: old >> 59)
        return (xs >> rot) | (xs << ((~rot &+ 1) & 31))
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt32(n)) }
    mutating func chance(_ permille: Int) -> Bool { below(1000) < permille }
    // triangular noise in [-w, w] (integer, no floats)
    mutating func tri(_ w: Int) -> Int { w == 0 ? 0 : below(w + 1) - below(w + 1) }
}

public struct Tier: Sendable {
    var name: String
    var margin: Int      // ticks kept in hand before the last safe moment
    var jitter: Int      // triangular +/- ticks on that margin
    var slipPermille: Int  // per-obstacle chance of a late read
    var slipLate: Int    // ticks late when it slips
    var rollPermille: Int // chance to plonk-roll a qualifying landing
    var routeNoise: Int  // centiseconds of noise on the route score
    var reactPermille: Int // chance to answer a visible threat with a guard
    var useDelay: Int    // ticks before a fresh knack is considered
    var noticePermille: Int // chance to notice a floor trap on approach
    var smart: Bool      // knows chokepoints, holds guards, saves for the finish
}
public let tiers: [Tier] = [
    Tier(name: "Errand",   margin: 14, jitter: 8, slipPermille: 70, slipLate: 14, rollPermille: 0,   routeNoise: 300, reactPermille: 100, useDelay: 150, noticePermille: 180, smart: false),
    Tier(name: "Regular",  margin: 10, jitter: 6, slipPermille: 40, slipLate: 14, rollPermille: 150, routeNoise: 180, reactPermille: 400, useDelay: 70, noticePermille: 380,  smart: false),
    Tier(name: "Express",  margin: 7,  jitter: 4, slipPermille: 15, slipLate: 12, rollPermille: 500, routeNoise: 80,  reactPermille: 750, useDelay: 25, noticePermille: 530,  smart: true),
    Tier(name: "Special",  margin: 5,  jitter: 2, slipPermille: 5,  slipLate: 10, rollPermille: 850, routeNoise: 30,  reactPermille: 950, useDelay: 8, noticePermille: 630,   smart: true),
    Tier(name: "Perfect",  margin: 4,  jitter: 0, slipPermille: 0,  slipLate: 0,  rollPermille: 1000, routeNoise: 0,  reactPermille: 1000, useDelay: 0, noticePermille: 1000,  smart: true),
]

public enum Plan: Equatable, Sendable { case none, hop(Int), tuck(Int), hopPlonk(Int, Int) }

struct Eval { var fail: Fail; var failAt: Int; var landAt: Int; var pressGrounded: Bool = true }

@inline(__always) func inputFor(_ p: Plan, _ t: Int) -> Input {
    var i = Input()
    switch p {
    case .none: break
    case .hop(let hold): i.hop = t < hold
    case .tuck(let hold): i.down = t < hold
    case .hopPlonk(let hold, let at): i.hop = t < hold; i.down = t >= at
    }
    return i
}

func bandFail(_ r: Runner, _ bands: [Band]) -> Bool {
    guard r.grounded else { return false }
    let col = r.x >> 16, row = r.y >> 16
    for b in bands where col >= b.x0 && col <= b.x1 {
        if row < b.yMin || row > b.yMax { return true }
    }
    return false
}

func probe(_ start: Runner, _ tick: Int, _ plan: Plan, delay: Int, horizon: Int, _ c: CourseData, _ bands: [Band], heldHop: Bool, heldDown: Bool, traps: [Trap] = []) -> Eval {
    var r = start
    var land = -1
    var wasAir = !start.grounded
    var e = Eval(fail: .none, failAt: horizon, landAt: -1)
    for t in 0..<horizon {
        var i = Input()
        if t == delay && !r.grounded { e.pressGrounded = false }
        if t >= delay { i = inputFor(plan, t - delay) }
        else { i.hop = heldHop; i.down = heldDown }
        step(&r, i, tick + t, c)
        if !r.alive || r.bonkFlag { e.fail = .bonk; e.failAt = t; break }
        if r.bumpFlag { e.fail = .bump; e.failAt = t; break }
        if bandFail(r, bands) { e.fail = .band; e.failAt = t; break }
        if traps.contains(where: { touches($0, r) }) { e.fail = .trap; e.failAt = t; break }
        if !r.grounded { wasAir = true }
        if land < 0 && wasAir && r.grounded { land = t }
        if r.finished >= 0 { break }
    }
    e.landAt = land
    return e
}

public struct Bot: Sendable {
    var tier: Tier
    var rng: PCG
    var plan: Plan = .none
    var planT = 0
    var pendingMargin = -1
    var pendingSlip = 0
    var bands: [Band] = []
    var entries: [Entry] = []
    init(tier: Tier, seed: UInt64, id: UInt64) { self.tier = tier; rng = PCG(seed: seed, seq: id + 11) }
    func options(_ r: Runner) -> [Plan] {
        [.hop(3), .hop(6), .hop(9), .hop(16), .tuck(30), .tuck(60), .tuck(100), .hopPlonk(4, 14), .hopPlonk(10, 20)]
    }
    func acceptable(_ e: Eval, _ plan: Plan) -> Bool {
        if e.fail == .none { return true }
        if e.landAt >= 0 && e.failAt > e.landAt + 14 { return true }
        return false
    }
    // The first plan airborne at the run's contact tick that lands clear of every noticed trap.
    func trapAnswer(_ r: Runner, _ tick: Int, _ c: CourseData, _ horizon: Int, _ traps: [Trap]) -> Plan? {
        guard !traps.isEmpty else { return nil }
        let run = probe(r, tick, .none, delay: 0, horizon: horizon, c, bands, heldHop: false, heldDown: false, traps: traps)
        guard run.fail == .trap else { return nil }
        return options(r).first { o in
            let e = probe(r, tick, o, delay: 0, horizon: horizon, c, bands, heldHop: false, heldDown: false, traps: traps)
            return acceptable(e, o) && e.landAt > run.failAt
        }
    }
    mutating func decide(_ r: Runner, _ tick: Int, _ c: CourseData, avoiding traps: [Trap] = []) -> Input {
        if !r.alive || r.finished >= 0 { plan = .none; planT = 0; return Input() }
        // route entry recipes outrank everything else
        if (r.grounded || r.coyote > 0), let e = entries.first {
            if r.x >= e.x {
                entries.removeFirst()
                if r.x < e.x + 2 * ONE { plan = e.plan; planT = 0; pendingMargin = -1; pendingSlip = 0 }
            }
        }
        // keep executing the current plan
        if plan != .none {
            let i = inputFor(plan, planT)
            planT += 1
            var done = false
            switch plan {
            case .hop(let h): done = planT >= h
            case .tuck(let h): done = planT >= h
            case .hopPlonk(_, let a): done = planT >= a && r.grounded
            default: break
            }
            if done {
                plan = .none; planT = 0
                // opportunistic plonk-roll after a real hop
            }
            return i
        }
        // airborne: optional plonk-roll
        if !r.grounded && r.coyote == 0 {
            if !r.plonking && r.vy < 0 && r.fallTop - r.y >= Tune.rollMinFall / 2 && r.coyote == 0 && tier.rollPermille > 0 {
                // decide once per descent using a cheap coin; roll only if landing is safe and at least 1.5 tiles down
                var s = r
                var ok = false
                var landed = false
                for t in 0..<40 {
                    step(&s, Input(hop: false, down: true), tick + t, c)
                    if s.bonkFlag || !s.alive || s.bumpFlag || traps.contains(where: { touches($0, s) }) { ok = false; break }
                    if s.grounded { landed = true; ok = s.rolls > r.rolls && !bandFail(s, bands); break }
                }
                if landed && ok && rng.chance(tier.rollPermille / 12 + 1) {
                    plan = .tuck(16); planT = 1
                    return Input(hop: false, down: true)
                }
            }
            return Input()
        }
        if bandFail(r, bands) { let col = r.x >> 16; bands.removeAll { col >= $0.x0 && col <= $0.x1 } }
        // grounded: does running straight survive?
        let horizon = 110
        let straight = probe(r, tick, .none, delay: 0, horizon: horizon, c, bands, heldHop: false, heldDown: false)
        if acceptable(straight, .none) {
            pendingMargin = -1; pendingSlip = 0
            if let o = trapAnswer(r, tick, c, horizon, traps) { plan = o; planT = 1; return inputFor(o, 0) }
            return Input()
        }
        // new obstacle: sample read quality once
        if pendingMargin < 0 {
            pendingMargin = max(0, tier.margin + rng.tri(tier.jitter))
            pendingSlip = rng.chance(tier.slipPermille) ? tier.slipLate : 0
        }
        // can we still wait? (plan must still work if started `margin` ticks from now)
        let opts = options(r)
        var canWait = false
        if pendingSlip == 0 {
            for o in opts {
                let e = probe(r, tick, o, delay: pendingMargin + 1, horizon: horizon + pendingMargin, c, bands, heldHop: false, heldDown: false)
                if e.pressGrounded && acceptable(e, o) { canWait = true; break }
            }
        } else {
            // a slip: keeps waiting past the point of no return for slipLate ticks
            var live = false
            for o in opts where acceptable(probe(r, tick, o, delay: 1, horizon: horizon, c, bands, heldHop: false, heldDown: false), o) { live = true; break }
            if live { canWait = true }
            else { pendingSlip -= 1; canWait = pendingSlip > 0 }
        }
        if canWait { return Input() }
        // act now: first acceptable option (shortest hop that works)
        for o in opts {
            let e = probe(r, tick, o, delay: 0, horizon: horizon, c, bands, heldHop: false, heldDown: false)
            if acceptable(e, o) {
                plan = o; planT = 1; pendingMargin = -1; pendingSlip = 0
                return inputFor(o, 0)
            }
        }
        // nothing works: panic full hop only if the failure is imminent
        if straight.failAt < 20 {
            plan = .hop(16); planT = 1; pendingMargin = -1; pendingSlip = 0
            return Input(hop: true, down: false)
        }
        return Input()
    }
}
