/// Canonical FNV-1a: field order below; integers are 64-bit little endian,
/// booleans 0/1, arrays count-prefixed, strings UTF-8 count-prefixed.
public func stateHash(_ s: RaceState) -> UInt64 {
    var h: UInt64=14695981039346656037
    func word(_ value: UInt64) {
        var v=value
        for _ in 0..<8 { h=(h ^ (v & 255)) &* 1099511628211; v >>= 8 }
    }
    func int(_ n: Int) { word(UInt64(bitPattern:Int64(n))) }
    func ints(_ a: [Int]) { int(a.count); for v in a { int(v) } }
    func bool(_ b: Bool) { int(b ? 1 : 0) }
    func text(_ t: String) { int(t.utf8.count); for b in t.utf8 { h=(h ^ UInt64(b)) &* 1099511628211 } }
    func plan(_ p: Plan) { switch p { case .none: int(0); case .hop(let a): int(1); int(a); case .tuck(let a): int(2); int(a); case .hopPlonk(let a,let b): int(3); int(a); int(b) } }
    int(1); word(s.config.seed); int(s.config.clockOffset)
    int(s.config.runners.count); for r in s.config.runners { int(r.botTier ?? -1); int(r.cast) }
    ints([s.tick,s.sequence,s.taxT,s.taxSender,s.trapGroup,s.playerFinishedAt]); bool(s.complete); int(Int(s.taxAffected)); int(Int(s.taxBlocked))
    int(s.runners.count)
    for r in s.runners {
        ints([r.guardT,r.immuneT,r.shakeT,r.stunT,r.x,r.y,r.vx,r.vy,r.coyote,r.hopBuf,r.fallTop,r.tuckTicks,r.roll,r.thud,r.bonkTimer,r.invuln,r.anchorX,r.anchorY,r.statusMul,r.statusT,r.speedMul,r.speedT,r.finished,r.bonks,r.bumps,r.rolls,r.stuckT,r.stuckX,r.noHopT,r.taxMul,r.streakAnchor,r.streak,r.mercies])
        for b in [r.hazardContact,r.grounded,r.prevHop,r.prevDown,r.rising,r.plonking,r.tucked,r.alive,r.bumpFlag,r.bonkFlag] { bool(b) }
    }
    int(s.inventories.count)
    for b in s.inventories { ints(b.hands); ints(b.acquired); ints(b.cooldowns); ints([b.lastUsed,b.lockout]); word(b.parcels); word(b.rng.state); word(b.rng.inc) }
    int(s.bots.count)
    for optional in s.bots {
        bool(optional != nil)
        if let b=optional {
            text(b.tier.name); ints([b.tier.margin,b.tier.jitter,b.tier.slipPermille,b.tier.slipLate,b.tier.rollPermille,b.tier.routeNoise,b.tier.reactPermille,b.tier.useDelay,b.tier.trapNotice]); bool(b.tier.smart)
            word(b.rng.state); word(b.rng.inc); plan(b.plan); ints([b.planT,b.pendingMargin,b.pendingSlip])
            int(b.bands.count); for band in b.bands { ints([band.x0,band.x1,band.yMin,band.yMax]) }
            int(b.entries.count); for e in b.entries { int(e.x); plan(e.plan) }
        }
    }
    int(s.routes.count); for routes in s.routes { ints(routes) }
    int(s.projectiles.count); for p in s.projectiles { ints([p.owner,p.x,p.y,p.remaining]) }
    int(s.traps.count); for t in s.traps { ints([t.owner,t.kind,t.x0,t.x1,t.y,t.life,t.group]); int(Int(t.triggered)); int(Int(t.rolled)); int(Int(t.noticed)) }
    int(s.events.count); for e in s.events { ints([e.tick,e.sequence,e.runner,e.kind,e.payload]) }
    return h
}
