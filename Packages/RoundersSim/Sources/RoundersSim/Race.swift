public enum Knack: Int, CaseIterable, Sendable {
    case paperDart, overdueBill, drawingPins, gumPatch, bubbleMailer, tamperSeal, tailwind, firstClass
    public var name: String { ["Paper Dart", "Overdue Bill", "Drawing Pins", "Gum Patch", "Bubble Mailer", "Tamper Seal", "Tailwind", "First Class"][rawValue] }
    public var category: Int { rawValue >> 1 }
    public var cooldown: Int { [480,900,480,600,540,600,480,360][rawValue] }
    public var icon: String { ["➤", "BILL", "•••", "GUM", "◉", "SEAL", ">>", "1st"][rawValue] }
}
public struct RunnerSetup: Sendable {
    /// nil is a human; 0...3 are the four bot tiers, 4 is the test-only no-error tier.
    public var botTier: Int?
    public var cast: Int
    public init(botTier: Int? = nil, cast: Int = 0) { self.botTier=botTier; self.cast=cast }
}
public struct RaceConfig: Sendable {
    public var seed: UInt64
    public var runners: [RunnerSetup]
    public var clockOffset: Int
    public init(seed: UInt64 = 42, runners: [RunnerSetup], clockOffset: Int = 2200) { self.seed=seed; self.runners=runners; self.clockOffset=clockOffset }
    public static func demo(seed: UInt64 = 42, regular: Bool = false, autoplay: Bool = false) -> RaceConfig {
        let field = regular ? [0,1,1,1,2] : [0,0,0,0,1]
        return RaceConfig(seed:seed,runners:[RunnerSetup(botTier:autoplay ? 1 : nil)] + field.enumerated().map { RunnerSetup(botTier:$0.element,cast:$0.offset+1) })
    }
}
public struct Inventory: Sendable {
    public var hands = [-1,-1]
    public var acquired = [0,0]
    public var cooldowns = [Int](repeating:0,count:8)
    public var lastUsed = -1
    public var lockout = 0
    public var parcels: UInt64 = 0
    public var rng: PCG
    public init(seed: UInt64, id: Int) { rng=PCG(seed:seed,seq:UInt64(id)+100) }
}
public struct Projectile: Sendable {
    public var owner, x, y, remaining: Int
}
public struct Trap: Sendable {
    public var owner, kind, x0, x1, y, life, group: Int
    public var triggered: UInt8 = 0
}
public struct SimEvent: Sendable {
    public var tick, sequence, runner, kind, payload: Int
    // hop, land, plonk, tuck, parcel, knack, bonk, finish, hit, block
}
public struct RaceState: Sendable {
    public var config: RaceConfig
    public var runners: [Runner]
    public var inventories: [Inventory]
    public var bots: [Bot?]
    public var routes: [[Int]]
    public var projectiles: [Projectile] = []
    public var traps: [Trap] = []
    public var events: [SimEvent] = []
    public var tick = 0, sequence = 0
    public var taxT = 0, taxSender = -1, trapGroup = 0
    public var playerFinishedAt = -1
    public var complete = false
    public var places: [Int] { runners.indices.sorted { a,b in
        let x=runners[a], y=runners[b]
        if x.finished >= 0 || y.finished >= 0 {
            if x.finished < 0 { return false }; if y.finished < 0 { return true }
            if x.finished != y.finished { return x.finished < y.finished }
        }
        return x.x == y.x ? a < b : x.x > y.x
    } }
}
public func makeRace(_ config: RaceConfig, course: CourseData) -> RaceState {
    precondition(config.runners.count == 6)
    var grid = Array(4...9)
    var rng=PCG(seed:config.seed,seq:1)
    for i in stride(from:5,through:1,by:-1) { grid.swapAt(i,rng.below(i+1)) }
    var runners: [Runner]=[]
    for x in grid {
        var r=Runner(); r.x=x*ONE+ONE/2; r.y=10*ONE; r.grounded=true
        r.anchorX=6*ONE+ONE/2; r.anchorY=10*ONE; r.stuckX=r.x
        runners.append(r)
    }
    return RaceState(config:config,runners:runners,inventories:(0..<6).map { Inventory(seed:config.seed,id:$0) },bots:config.runners.enumerated().map { i,s in s.botTier.map { Bot(tier:tiers[$0],seed:config.seed,id:UInt64(i)) } },routes:[[Int]](repeating:[Int](repeating:-1,count:course.forks.count),count:6))
}
public func emit(_ s: inout RaceState, _ runner: Int, _ kind: Int, _ payload: Int = 0) {
    s.events.append(SimEvent(tick:s.tick,sequence:s.sequence,runner:runner,kind:kind,payload:payload)); s.sequence += 1
    if s.events.count > 64 { s.events.removeFirst(s.events.count-64) }
}
public let rollWeights = [[60,160,140,40],[90,130,120,70],[100,110,100,90],[110,90,100,110],[125,70,90,130],[140,50,80,160]]
public func rollKnack(_ inventory: inout Inventory, place: Int) -> Int {
    let eligible=(0..<8).filter { inventory.cooldowns[$0] == 0 && $0 != inventory.lastUsed }
    // No eligible entry: parcel is spent, leaving the hand empty.
    let total=eligible.reduce(0) { $0+rollWeights[place][$1 >> 1] }
    guard total > 0 else { return -1 }
    var draw=inventory.rng.below(total)
    for k in eligible { draw -= rollWeights[place][k >> 1]; if draw < 0 { return k } }
    return -1
}
public func dartTarget(_ s: RaceState, owner: Int, course: CourseData) -> Int? {
    let r=s.runners[owner], y=r.y+78643 // 1.2 tiles: standing hit, tucked dodge
    return s.runners.indices.filter { j in
        let v=s.runners[j]
        guard j != owner && v.alive && v.finished < 0 && v.x > r.x && v.x-r.x <= 18*ONE && y >= v.y && y <= v.y+(v.tucked ? Tune.hTuck : Tune.hStand) else { return false }
        for x in (r.x >> 16)...(v.x >> 16) where isSolid(course.at(x,y >> 16),false) { return false }
        return true
    }.min { a,b in s.runners[a].x == s.runners[b].x ? a < b : s.runners[a].x < s.runners[b].x }
}
public func canUse(_ s: RaceState, runner: Int, hand: Int, course: CourseData) -> Bool {
    let r=s.runners[runner], bag=s.inventories[runner], k=bag.hands[hand]
    guard r.alive && r.finished < 0 && bag.lockout == 0 && k >= 0 && (r.stunT == 0 || k == Knack.tamperSeal.rawValue) else { return false }
    if k == 0 { return dartTarget(s,owner:runner,course:course) != nil }
    if k == 1 { return s.places.first != runner }
    return true
}
public func applyHit(_ s: inout RaceState, target: Int, multiplier: Int, duration: Int, gum: Bool = false) {
    guard s.runners[target].alive && s.runners[target].finished < 0 && s.runners[target].invuln == 0 else { return }
    if s.runners[target].guardT > 0 { s.runners[target].guardT=0; emit(&s,target,9); return }
    if s.runners[target].immuneT > 0 || s.runners[target].shakeT > 0 { return }
    let old=s.runners[target].statusT > 0 ? s.runners[target].statusMul : ONE
    if multiplier <= old { s.runners[target].statusMul=multiplier; s.runners[target].statusT=duration }
    if gum { s.runners[target].noHopT=max(s.runners[target].noHopT,30) }
    s.runners[target].shakeT=45; emit(&s,target,8)
}
public func useKnack(_ s: inout RaceState, runner id: Int, hand: Int, course: CourseData) {
    guard canUse(s,runner:id,hand:hand,course:course), let k=Knack(rawValue:s.inventories[id].hands[hand]) else { return }
    let r=s.runners[id]
    switch k {
    case .paperDart:
        if s.projectiles.count < 32 { s.projectiles.append(Projectile(owner:id,x:r.x+Tune.w/2,y:r.y+78643,remaining:18*ONE)) }
    case .overdueBill: s.taxT=360; s.taxSender=id
    case .drawingPins, .gumPatch:
        s.trapGroup += 1
        let groups=s.traps.filter { $0.owner == id }.map { $0.group }
        let unique=groups.enumerated().filter { i,g in !groups.prefix(i).contains(g) }.map { $0.element }
        if unique.count >= 3, let first=unique.first { s.traps.removeAll { $0.owner == id && $0.group == first } }
        let ranges=k == .drawingPins ? [(98304,26214),(196608,26214),(294912,26214)] : [(3*ONE,2*ONE)]
        for (behind,half) in ranges {
            let x=r.x-behind
            var floorY: Int? = nil
            for dy in 0...12 {
                let row=(r.y >> 16)-1-dy
                if row >= 0 && (isSolid(course.at(x >> 16,row),false) || isTop(course.at(x >> 16,row))) { floorY=(row+1)*ONE; break }
            }
            if let y=floorY, s.traps.count < 54 { s.traps.append(Trap(owner:id,kind:k.rawValue,x0:x-half,x1:x+half,y:y,life:k == .drawingPins ? 720 : 600,group:s.trapGroup)) }
        }
    case .bubbleMailer: s.runners[id].guardT=180
    case .tamperSeal:
        s.runners[id].statusT=0; s.runners[id].statusMul=ONE; s.runners[id].noHopT=0; s.runners[id].stunT=0; s.runners[id].shakeT=0; s.runners[id].immuneT=120
    case .tailwind: s.runners[id].speedT=151; s.runners[id].speedMul=81920
    case .firstClass: s.runners[id].speedT=73; s.runners[id].speedMul=91750; s.runners[id].vx=qmul(Tune.vBase,91750)
    }
    s.inventories[id].hands[hand] = -1; s.inventories[id].lockout=30
    s.inventories[id].lastUsed=k.rawValue; s.inventories[id].cooldowns[k.rawValue]=k.cooldown
    emit(&s,id,5,k.rawValue)
}
func chooseRoutes(_ s: inout RaceState, _ id: Int, _ c: CourseData) {
    guard var bot=s.bots[id] else { return }
    for (fi,f) in c.forks.enumerated() where s.routes[id][fi] < 0 && s.runners[id].x >= (f.x0-24)*ONE {
        let empty=s.inventories[id].hands.filter { $0 < 0 }.count
        var scores: [Int]=[]
        for r in f.routes { scores.append(r.deltaCs+r.risk*(bot.tier.smart ? 40 : 90)-r.parcelDelta*empty*30+bot.rng.tri(bot.tier.routeNoise)) }
        let ri=scores.indices.min { scores[$0] == scores[$1] ? $0 < $1 : scores[$0] < scores[$1] }!
        s.routes[id][fi]=ri; bot.bands += f.routes[ri].bands; bot.entries += f.routes[ri].entries
    }
    s.bots[id]=bot
}
func botHand(_ s: inout RaceState, _ id: Int, _ c: CourseData) -> Int? {
    guard var bot=s.bots[id] else { return nil }
    defer { s.bots[id]=bot }
    let r=s.runners[id], place=s.places.firstIndex(of:id)!, late=r.x > c.finishX*ONE*85/100
    let ahead=dartTarget(s,owner:id,course:c) != nil
    let behind=s.runners.indices.contains { $0 != id && s.runners[$0].alive && s.runners[$0].x < r.x && r.x-s.runners[$0].x < 14*ONE }
    let threat=s.projectiles.contains { $0.owner != id && $0.x < r.x && r.x-$0.x < 8*ONE && abs($0.y-r.y-ONE) < ONE } || c.hazards.contains { $0.x0*ONE > r.x && $0.x0*ONE-r.x < 4*ONE && abs($0.y0-r.y) < 2*ONE }
    for h in 0..<2 {
        let raw=s.inventories[id].hands[h]
        guard let k=Knack(rawValue:raw), s.tick-s.inventories[id].acquired[h] >= bot.tier.useDelay else { continue }
        let stale=s.tick-s.inventories[id].acquired[h] > 420
        var use=false
        switch k {
        case .paperDart: use=ahead
        case .overdueBill: use=place > 0 && (!bot.tier.smart || place <= 3 || late)
        case .drawingPins,.gumPatch: use=behind && (!bot.tier.smart || late || stale || c.chokepoints.contains { abs($0*ONE-r.x)<3*ONE }) || (!bot.tier.smart && stale)
        case .bubbleMailer: use=(threat && bot.rng.chance(bot.tier.reactPermille)) || (!bot.tier.smart && stale)
        case .tamperSeal: use=r.statusT > 0 || r.noHopT > 0 || r.stunT > 0 || (!bot.tier.smart && stale)
        case .tailwind,.firstClass: use=r.grounded && (!bot.tier.smart || r.vx >= Tune.vBase && (place > 0 || late || stale))
        }
        if use { return h }
    }
    return nil
}
public func step(_ s: inout RaceState, inputs: [InputFrame], course c: CourseData) {
    guard !s.complete else { return }
    let places=s.places
    if s.taxT > 0 { s.taxT -= 1 }
    for id in 0..<6 {
        s.runners[id].taxMul = s.taxT > 0 && places.first == id && id != s.taxSender && s.runners[id].immuneT == 0 ? 58982 : ONE
    }
    for n in 0..<6 {
        let id=(n+s.tick)%6
        chooseRoutes(&s,id,c)
        for k in 0..<8 { s.inventories[id].cooldowns[k]=max(0,s.inventories[id].cooldowns[k]-1) }
        s.inventories[id].lockout=max(0,s.inventories[id].lockout-1)
        s.runners[id].guardT=max(0,s.runners[id].guardT-1); s.runners[id].immuneT=max(0,s.runners[id].immuneT-1)
        s.runners[id].shakeT=max(0,s.runners[id].shakeT-1); s.runners[id].stunT=max(0,s.runners[id].stunT-1)
        var frame = id < inputs.count ? inputs[id] : InputFrame()
        if var bot=s.bots[id] {
            let movement=bot.decide(s.runners[id],s.tick+s.config.clockOffset,c)
            s.bots[id]=bot
            frame=InputFrame(bits:(movement.hop ? 1 : 0)|(movement.down ? 2 : 0))
            if let h=botHand(&s,id,c) { frame.bits |= h == 0 ? 4 : 8 }
        }
        // Hands are press events supplied by the app. Left wins simultaneous use.
        if frame.has(4) { useKnack(&s,runner:id,hand:0,course:c) }
        else if frame.has(8) { useKnack(&s,runner:id,hand:1,course:c) }
        let old=s.runners[id]
        let input=Input(hop:frame.has(1) && old.stunT == 0,down:frame.has(2) && old.stunT == 0)
        if old.stunT > 0 { s.runners[id].vx=0 }
        step(&s.runners[id],input,s.tick+s.config.clockOffset,c)
        if old.stunT > 0 { s.runners[id].x=old.x; s.runners[id].vx=0 }
        if s.runners[id].finished >= 0 && old.finished < 0 { s.runners[id].finished=s.tick; emit(&s,id,7) }
        if old.alive && !s.runners[id].alive { emit(&s,id,6) }
        if old.grounded && !s.runners[id].grounded && s.runners[id].vy > 0 { emit(&s,id,0) }
        if !old.grounded && s.runners[id].grounded { emit(&s,id,1,s.runners[id].roll > 0 ? 1 : 0) }
        if !old.plonking && s.runners[id].plonking { emit(&s,id,2) }
        if !old.tucked && s.runners[id].tucked { emit(&s,id,3) }
        let r=s.runners[id]
        guard r.alive && r.finished < 0 else { continue }
        for (pi,p) in c.parcels.enumerated() where s.inventories[id].parcels & (UInt64(1)<<pi) == 0 && abs(r.x-(p.x*ONE+ONE/2)) <= ONE && p.y*ONE < r.y+(r.tucked ? Tune.hTuck : Tune.hStand)+ONE/2 && (p.y+1)*ONE > r.y {
            s.inventories[id].parcels |= UInt64(1)<<pi
            if let h=s.inventories[id].hands.firstIndex(of:-1) {
                s.inventories[id].hands[h]=rollKnack(&s.inventories[id],place:places.firstIndex(of:id)!)
                s.inventories[id].acquired[h]=s.tick
            }
            emit(&s,id,4)
        }
        for ti in s.traps.indices {
            let t=s.traps[ti]
            if t.life > 0 && t.owner != id && t.triggered & (1<<id) == 0 && r.x+Tune.w/2 > t.x0 && r.x-Tune.w/2 < t.x1 && r.y < t.y+ONE/3 && r.y+Tune.hStand > t.y {
                applyHit(&s,target:id,multiplier:t.kind == 2 ? 36045 : 45875,duration:36,gum:t.kind == 3)
                s.traps[ti].triggered |= 1<<id
                if t.kind == 2 { s.traps[ti].life=0 }
            }
        }
    }
    for ti in s.traps.indices { s.traps[ti].life -= 1 }; s.traps.removeAll { $0.life <= 0 }
    for pi in s.projectiles.indices {
        let p=s.projectiles[pi], next=p.x+24030 // 22 tiles/s, Q16
        var stop=false
        for x in (p.x >> 16)...(next >> 16) where isSolid(c.at(x,p.y >> 16),false) { stop=true }
        if !stop {
            let targets=s.runners.indices.filter { id in let r=s.runners[id]; return id != p.owner && r.alive && r.finished < 0 && r.x+Tune.w/2 >= p.x && r.x-Tune.w/2 <= next && p.y+6554 >= r.y && p.y-6554 <= r.y+(r.tucked ? Tune.hTuck : Tune.hStand) }
            if let target=targets.min(by:{ s.runners[$0].x == s.runners[$1].x ? $0 < $1 : s.runners[$0].x < s.runners[$1].x }) { applyHit(&s,target:target,multiplier:36045,duration:54); stop=true }
        }
        s.projectiles[pi].x=next; s.projectiles[pi].remaining -= 24030
        if stop { s.projectiles[pi].remaining=0 }
    }
    s.projectiles.removeAll { $0.remaining <= 0 }
    if s.runners[0].finished >= 0 && s.playerFinishedAt < 0 { s.playerFinishedAt=s.tick }
    s.tick += 1
    s.complete=s.runners.allSatisfy { $0.finished >= 0 } || (s.playerFinishedAt >= 0 && s.tick-s.playerFinishedAt >= 600) || s.tick >= 10800
}
