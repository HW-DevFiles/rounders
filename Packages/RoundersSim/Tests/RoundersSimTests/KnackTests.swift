import XCTest
@testable import RoundersSim

func arena() -> RaceState {
    let c=flat()
    var s=makeRace(RaceConfig(seed:42,runners:(0..<6).map { RunnerSetup(cast:$0) }),course:c)
    for i in 0..<6 { s.runners[i]=running((20+i*3)*ONE) }
    return s
}
func give(_ s: inout RaceState,_ k: Knack,to id: Int = 0,hand: Int = 0) { s.inventories[id].hands[hand]=k.rawValue }
func trapRun(tier: Int,seed: UInt64,_ k: Knack) -> (hit: Bool,state: RaceState) {
    let c=flat()
    var s=makeRace(RaceConfig(seed:seed,runners:(0..<6).map { RunnerSetup(botTier:$0 == 1 ? tier : nil,cast:$0) }),course:c)
    for i in 0..<6 { s.runners[i]=running((200+i*3)*ONE) }
    s.runners[1]=running(20*ONE); s.runners[0].x=40*ONE; give(&s,k)
    useKnack(&s,runner:0,hand:0,course:c)
    s.runners[0].x=200*ONE
    var hit=false
    while s.runners[1].x < 42*ONE { step(&s,inputs:[],course:c); hit=hit || s.runners[1].shakeT > 0 }
    return (hit,s)
}
final class KnackTests: XCTestCase {
    func testPaperDartSpeedRangeGeometryAndStagger() {
        let c=flat(); var s=arena(); give(&s,.paperDart)
        useKnack(&s,runner:0,hand:0,course:c)
        XCTAssertEqual(s.projectiles.count,1); XCTAssertEqual(s.projectiles[0].remaining,18*ONE)
        let start=s.projectiles[0].x; step(&s,inputs:[],course:c)
        XCTAssertEqual(s.projectiles[0].x-start,24030)
        for _ in 0..<30 { step(&s,inputs:[],course:c) }
        XCTAssertGreaterThan(s.runners[1].statusT,0); XCTAssertEqual(s.runners[1].statusMul,36045)
        var t=arena(); t.runners[1].tucked=true; t.runners[1].prevDown=true
        give(&t,.paperDart); XCTAssertEqual(dartTarget(t,owner:0,course:c),2)
        // Full hit duration is independently asserted at the collision interface.
        applyHit(&t,target:1,multiplier:36045,duration:54); XCTAssertEqual(t.runners[1].statusT,54)
        var wall=c; wall.t[11*c.w+22]=35
        t=arena(); give(&t,.paperDart); XCTAssertNil(dartTarget(t,owner:0,course:wall)); useKnack(&t,runner:0,hand:0,course:wall); XCTAssertEqual(t.inventories[0].hands[0],0)
    }
    func testOverdueBillFollowsLeaderAndSenderExempt() {
        let c=flat(); var s=arena(); give(&s,.overdueBill)
        useKnack(&s,runner:0,hand:0,course:c); XCTAssertEqual(s.taxT,360)
        step(&s,inputs:[],course:c); XCTAssertEqual(s.runners[5].taxMul,58982)
        s.runners[0].x=50*ONE; step(&s,inputs:[],course:c); XCTAssertEqual(s.runners[0].taxMul,ONE); XCTAssertEqual(s.runners[5].taxMul,ONE)
        s.taxT=1; step(&s,inputs:[],course:c); XCTAssertEqual(s.taxT,0)
    }
    func testOverdueBillSkipsFinishedRunnersAndMovesOnWhenLeaderFinishes() {
        let c=flat(); var s=arena(); give(&s,.overdueBill)
        useKnack(&s,runner:0,hand:0,course:c)
        step(&s,inputs:[],course:c); XCTAssertEqual(s.runners[5].taxMul,58982)
        s.runners[5].finished=s.tick; step(&s,inputs:[],course:c)
        XCTAssertEqual(s.runners[5].taxMul,ONE); XCTAssertEqual(s.runners[4].taxMul,58982)
    }
    func testOverdueBillDimsAndIsKeptWhenOnlyFinishedRunnersAreAhead() {
        let c=flat(); var s=arena(); s.runners[5].finished=0
        give(&s,.overdueBill,to:4); XCTAssertFalse(canUse(s,runner:4,hand:0,course:c))
        step(&s,inputs:[InputFrame(),InputFrame(),InputFrame(),InputFrame(),InputFrame(bits:4)],course:c)
        XCTAssertEqual(s.inventories[4].hands[0],1); XCTAssertEqual(s.inventories[4].lockout,0); XCTAssertEqual(s.taxT,0)
        give(&s,.overdueBill,to:3); XCTAssertTrue(canUse(s,runner:3,hand:0,course:c))
    }
    func testBotKeepsBillWithOnlyFinishedRunnersAheadAndStillUsesOtherHand() {
        let c=flat()
        var s=makeRace(RaceConfig(seed:42,runners:(0..<6).map { RunnerSetup(botTier:$0 == 4 ? 0 : nil,cast:$0) }),course:c)
        for i in 0..<6 { s.runners[i]=running((20+i*3)*ONE) }
        s.runners[5].finished=0; s.tick=1000
        give(&s,.overdueBill,to:4); give(&s,.firstClass,to:4,hand:1)
        step(&s,inputs:[],course:c)
        XCTAssertEqual(s.inventories[4].hands,[1,-1]); XCTAssertEqual(s.taxT,0)
    }
    func testBillGuardBlocksThisBillAcrossLeadChanges() {
        let c=flat(); var s=arena(); give(&s,.overdueBill)
        s.runners[5].guardT=180
        useKnack(&s,runner:0,hand:0,course:c)
        step(&s,inputs:[],course:c)
        XCTAssertEqual(s.runners[5].guardT,0); XCTAssertEqual(s.runners[5].taxMul,ONE)
        s.runners[4].x=50*ONE; step(&s,inputs:[],course:c); XCTAssertEqual(s.runners[4].taxMul,58982)
        s.runners[5].x=60*ONE; step(&s,inputs:[],course:c); XCTAssertEqual(s.runners[5].taxMul,ONE)
        // Another Bill resets eligibility; Seal clears Tax on the same use tick.
        s.inventories[0].lockout=0; give(&s,.overdueBill)
        useKnack(&s,runner:0,hand:0,course:c); step(&s,inputs:[],course:c)
        XCTAssertEqual(s.runners[5].taxMul,58982)
        give(&s,.tamperSeal,to:5); step(&s,inputs:[InputFrame(),InputFrame(),InputFrame(),InputFrame(),InputFrame(),InputFrame(bits:4)],course:c)
        XCTAssertEqual(s.runners[5].taxMul,ONE)
    }
    func testDrawingPinsAndOwnerImmunity() {
        let c=flat(); var s=arena(); give(&s,.drawingPins)
        useKnack(&s,runner:0,hand:0,course:c)
        XCTAssertEqual(s.traps.count,3); XCTAssertEqual(s.traps.map { $0.life },[720,720,720])
        XCTAssertEqual(s.traps.map { (s.runners[0].x-($0.x0+$0.x1)/2) },[98304,196608,294912])
        XCTAssertEqual(s.traps[0].x1-s.traps[0].x0,52428)
        s.runners[1].x=(s.traps[0].x0+s.traps[0].x1)/2; step(&s,inputs:[],course:c)
        XCTAssertEqual(s.runners[1].statusT,36); XCTAssertEqual(s.runners[0].statusT,0); XCTAssertEqual(s.traps.count,2)
    }
    func testGumOncePerRunnerNoHopAndLifetime() {
        let c=flat(); var s=arena(); give(&s,.gumPatch)
        useKnack(&s,runner:0,hand:0,course:c)
        XCTAssertEqual(s.traps[0].x0,15*ONE); XCTAssertEqual(s.traps[0].x1,19*ONE); XCTAssertEqual(s.traps[0].life,600)
        s.runners[1].x=17*ONE; step(&s,inputs:[],course:c)
        XCTAssertEqual(s.runners[1].statusMul,45875); XCTAssertEqual(s.runners[1].statusT,36); XCTAssertEqual(s.runners[1].noHopT,30)
        step(&s,inputs:[InputFrame(),InputFrame(bits:1)],course:c); XCTAssertTrue(s.runners[1].grounded)
        XCTAssertEqual(s.runners[1].statusT,35)
    }
    func testBotsNoticeFloorTrapsAtTierRates() {
        var rates: [[Int]]=[]
        for tier in 0..<4 { rates.append([Knack.drawingPins,.gumPatch].map { k in (0..<1000).filter { !trapRun(tier:tier,seed:UInt64($0),k).hit }.count }) }
        for (tier,expected) in [180,380,530,630].enumerated() { for rate in rates[tier] { XCTAssertEqual(rate,expected,accuracy:60) } }
    }
    func testNoticedTrapIsHoppedAndRollIsPerEncounter() {
        for k in [Knack.drawingPins,.gumPatch] {
            let (hit,s)=trapRun(tier:4,seed:42,k)
            XCTAssertFalse(hit); XCTAssertEqual(s.runners[1].bonks,0); XCTAssertGreaterThan(s.runners[1].x,42*ONE)
            XCTAssertTrue(s.traps.allSatisfy { $0.rolled == 2 && $0.noticed == 2 })
            XCTAssertEqual(stateHash(trapRun(tier:4,seed:42,k).state),stateHash(s))
        }
    }
    func testTrapIsRolledOnlyOnTheBotsPathWithinLookAhead() {
        let c=flat()
        var s=makeRace(RaceConfig(seed:42,runners:(0..<6).map { RunnerSetup(botTier:$0 == 1 ? 4 : nil,cast:$0) }),course:c)
        for i in 0..<6 { s.runners[i]=running((200+i*3)*ONE) }
        s.runners[1]=running(20*ONE)
        s.traps=[Trap(owner:0,kind:3,x0:30*ONE,x1:34*ONE,y:12*ONE,life:600,group:1),Trap(owner:0,kind:3,x0:60*ONE,x1:64*ONE,y:10*ONE,life:600,group:2)]
        step(&s,inputs:[],course:c)
        XCTAssertEqual(s.traps.map { $0.rolled },[0,0])
        while s.runners[1].x < 66*ONE { step(&s,inputs:[],course:c) }
        XCTAssertEqual(s.traps.map { $0.rolled },[0,2])
    }
    func testBubbleMailerOneHitThreeSecondsAndContinuousHazard() {
        var c=flat(); var s=arena(); give(&s,.bubbleMailer)
        useKnack(&s,runner:0,hand:0,course:c); XCTAssertEqual(s.runners[0].guardT,180)
        applyHit(&s,target:0,multiplier:36045,duration:54)
        XCTAssertEqual(s.runners[0].guardT,0); XCTAssertEqual(s.runners[0].statusT,0)
        applyHit(&s,target:0,multiplier:36045,duration:54); XCTAssertEqual(s.runners[0].statusT,54)
        var r=running(20*ONE); r.guardT=180
        c.hazards=[Hazard(x0:19,x1:25,y0:10*ONE,y1:12*ONE,period:180,on:180,phase:0,kind:"peg")]
        for tick in 0..<30 { step(&r,Input(),tick,c); XCTAssertTrue(r.alive) }
        XCTAssertEqual(r.guardT,0)
        r.y = -ONE; r.guardT=180; step(&r,Input(),31,c); XCTAssertFalse(r.alive)
    }
    func testTamperSealClearsStatusUsableDuringStunAndImmuneTax() {
        let c=flat(); var s=arena(); give(&s,.tamperSeal)
        s.runners[0].stunT=20; s.runners[0].noHopT=30; s.runners[0].statusT=54; s.runners[0].statusMul=36045
        useKnack(&s,runner:0,hand:0,course:c)
        XCTAssertEqual(s.runners[0].stunT,0); XCTAssertEqual(s.runners[0].noHopT,0); XCTAssertEqual(s.runners[0].statusT,0); XCTAssertEqual(s.runners[0].immuneT,120)
        applyHit(&s,target:0,multiplier:36045,duration:54); XCTAssertEqual(s.runners[0].statusT,0)
        s.runners[0].x=50*ONE; s.taxT=360; s.taxSender=1
        step(&s,inputs:[],course:c); XCTAssertEqual(s.runners[0].taxMul,ONE)
    }
    func testTailwindAndFirstClassReplaceEachOther() {
        let c=flat(); var s=arena(); give(&s,.tailwind)
        step(&s,inputs:[InputFrame(bits:4)],course:c)
        XCTAssertEqual(s.runners[0].speedMul,81920); XCTAssertEqual(s.runners[0].speedT,150)
        s.inventories[0].lockout=0; give(&s,.firstClass)
        step(&s,inputs:[InputFrame(bits:4)],course:c)
        XCTAssertEqual(s.runners[0].speedMul,91750); XCTAssertEqual(s.runners[0].speedT,72); XCTAssertEqual(s.runners[0].vx,qmul(Tune.vBase,91750))
        for _ in 0..<72 { step(&s,inputs:[],course:c) }; XCTAssertEqual(s.runners[0].speedT,0); XCTAssertEqual(s.runners[0].speedMul,ONE)
    }
    func testLockoutCooldownAndSimultaneousLeftPriority() {
        let c=flat(); var s=arena(); give(&s,.bubbleMailer); give(&s,.tailwind,hand:1)
        step(&s,inputs:[InputFrame(bits:12)],course:c)
        XCTAssertEqual(s.inventories[0].hands,[-1,6]); XCTAssertEqual(s.inventories[0].lockout,30); XCTAssertEqual(s.inventories[0].cooldowns[4],540)
        for _ in 0..<29 { step(&s,inputs:[InputFrame(bits:8)],course:c) }
        XCTAssertEqual(s.inventories[0].hands[1],6)
        step(&s,inputs:[InputFrame(bits:8)],course:c); XCTAssertEqual(s.inventories[0].hands[1],-1)
    }
    func testShakeOffStrongestSlowAndSpeedClamp() {
        var s=arena(); applyHit(&s,target:0,multiplier:36045,duration:54)
        applyHit(&s,target:0,multiplier:45875,duration:90,gum:true)
        XCTAssertEqual(s.runners[0].statusT,54); XCTAssertEqual(s.runners[0].noHopT,0); XCTAssertEqual(s.runners[0].shakeT,45)
        s.runners[0].shakeT=0; applyHit(&s,target:0,multiplier:45875,duration:90)
        XCTAssertEqual(s.runners[0].statusMul,36045); XCTAssertEqual(s.runners[0].statusT,54)
        var c=flat(); for x in 0..<c.w { c.t[9*c.w+x]=62 }
        var r=running(); r.speedMul=2*ONE; r.speedT=100; r.vx=3*Tune.vBase
        for tick in 0..<80 { step(&r,Input(),tick,c) }
        XCTAssertEqual(r.vx,qmul(Tune.vBase,111411))
        r=running(); r.statusMul=ONE/4; r.statusT=200; r.taxMul=58982
        for tick in 0..<80 { step(&r,Input(),tick,flat()) }
        XCTAssertEqual(r.vx,qmul(Tune.vBase,29491))
    }
    func testParcelPerRunnerFullHandsWasteAndNoRefillOnBonk() {
        var c=flat(); c.parcels=[Point(20,10)]; var s=arena()
        s.runners[1].x=s.runners[0].x; s.inventories[0].hands=[4,6]
        step(&s,inputs:[],course:c)
        XCTAssertEqual(s.inventories[0].parcels,1); XCTAssertEqual(s.inventories[0].hands,[4,6]); XCTAssertEqual(s.inventories[1].parcels,1)
        s.inventories[0].hands=[-1,-1]; s.runners[0].alive=false; s.runners[0].bonkTimer=1
        step(&s,inputs:[],course:c); XCTAssertEqual(s.inventories[0].parcels,1)
    }
    func testRollWeightsCooldownNoRepeatAndNoEligibleFallback() {
        XCTAssertEqual(rollWeights,[[60,160,140,40],[90,130,120,70],[100,110,100,90],[110,90,100,110],[125,70,90,130],[140,50,80,160]])
        var bag=Inventory(seed:42,id:0); bag.lastUsed=0; bag.cooldowns[1]=900
        var counts=[Int](repeating:0,count:4)
        for _ in 0..<20000 { let k=rollKnack(&bag,place:5); XCTAssertNotEqual(k,0); XCTAssertNotEqual(k,1); counts[k >> 1] += 1 }
        XCTAssertGreaterThan(counts[3],counts[2]); XCTAssertGreaterThan(counts[2],counts[1])
        bag.cooldowns=[Int](repeating:1,count:8); XCTAssertEqual(rollKnack(&bag,place:0),-1)
    }
    func testAntiStuckAndBonkKeepsInventoryButClearsStatuses() {
        var c=flat(); for y in 10...14 { c.t[y*c.w+21]=35 }
        var r=running(21*ONE-Tune.w/2); r.vx=0; r.stuckX=r.x
        for tick in 0..<299 { step(&r,Input(),tick,c); XCTAssertTrue(r.alive) }
        step(&r,Input(),299,c); XCTAssertFalse(r.alive); XCTAssertEqual(r.bonkTimer,66)
        r.statusT=20; r.speedT=20; r.noHopT=20
        for tick in 0..<66 { step(&r,Input(),tick,c) }
        XCTAssertTrue(r.alive); XCTAssertEqual(r.statusT,0); XCTAssertEqual(r.speedT,0); XCTAssertEqual(r.noHopT,0)
    }
}
