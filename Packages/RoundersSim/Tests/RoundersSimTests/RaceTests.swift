import XCTest
@testable import RoundersSim
import RoundersContent

func solo(_ course: CourseData,tier: Int,seed: UInt64,forced: [Int] = [1,0,1]) -> (Runner,Int,Int) {
    var r=running(); r.vx=0
    var bot=Bot(tier:tiers[tier],seed:seed,id:0)
    for (f,ri) in zip(course.forks,forced) { bot.bands += f.routes[ri].bands; bot.entries += f.routes[ri].entries }
    var on=0,total=0
    for tick in 0..<10800 {
        let input=bot.decide(r,tick+2200,course); step(&r,input,tick+2200,course)
        for band in bot.bands where r.x >> 16 >= band.x0 && r.x >> 16 <= band.x1 {
            total += 1
            if r.y >> 16 >= band.yMin && r.y >> 16 <= band.yMax { on += 1 }
        }
        if r.finished >= 0 { r.finished=tick; break }
    }
    return (r,on,total)
}
final class RaceTests: XCTestCase {
    func testSevenRoutes() throws {
        let c=try CourseLoader.laundryLane()
        for (forced,expected) in [([0,0,1],63.60),([1,0,1],65.42),([2,0,1],66.07),([1,0,1],65.42),([1,1,1],64.67),([1,0,0],63.48),([1,0,1],65.42)] {
            let (r,on,total)=solo(c,tier:4,seed:42,forced:forced)
            print("ROUTE \(forced) tick=\(r.finished) bonks=\(r.bonks) band=\(on)/\(total)")
            XCTAssertGreaterThan(r.finished,0); XCTAssertEqual(r.bonks,0)
            XCTAssertGreaterThan(total,0); XCTAssertEqual(on,total)
            XCTAssertEqual(Double(r.finished)/60,expected,accuracy:1)
        }
    }
    func testTierLadder40Seeds() throws {
        let c=try CourseLoader.laundryLane()
        var totals: [Int]=[]
        for tier in 0..<4 {
            var total=0
            for seed in 0..<40 {
                let (r,_,_)=solo(c,tier:tier,seed:UInt64(seed))
                XCTAssertGreaterThan(r.finished,0); total += r.finished
            }
            totals.append(total); print("TIER \(tier) mean \(Double(total)/2400)")
        }
        XCTAssertGreaterThan(totals[0],totals[1]); XCTAssertGreaterThan(totals[1],totals[2]); XCTAssertGreaterThan(totals[2],totals[3])
    }
    func testFullRaceReplayAndRollback() throws {
        let c=try CourseLoader.laundryLane()
        let config=RaceConfig.demo(seed:42,regular:true,autoplay:true)
        var a=makeRace(config,course:c), b=a
        while !a.complete { step(&a,inputs:[],course:c) }
        while !b.complete {
            let snapshot=b
            for _ in 0..<30 where !b.complete { step(&b,inputs:[],course:c) }
            let expected=stateHash(b), ticks=b.tick-snapshot.tick
            if ticks >= 8 {
                b=snapshot
                for _ in 0..<(ticks-8) { step(&b,inputs:[],course:c) }
                let rewind=b
                for _ in 0..<8 { step(&b,inputs:[],course:c) }
                b=rewind
                for _ in 0..<8 { step(&b,inputs:[],course:c) }
            }
            XCTAssertEqual(stateHash(b),expected)
        }
        XCTAssertEqual(stateHash(a),stateHash(b)); XCTAssertEqual(a.runners.filter { $0.finished >= 0 }.count,6)
        XCTAssertEqual(stateHash(a),0x4c6797aa9901e818)
    }
    func testReplayHashCoversRNGPlansParcelsAndEvents() throws {
        let c=try CourseLoader.laundryLane(), s=makeRace(.demo(),course:c)
        var b=s; b.inventories[0].rng.state &+= 1; XCTAssertNotEqual(stateHash(s),stateHash(b))
        b=s; b.bots[1]!.planT += 1; XCTAssertNotEqual(stateHash(s),stateHash(b))
        b=s; b.inventories[0].parcels=1; XCTAssertNotEqual(stateHash(s),stateHash(b))
        b=s; emit(&b,0,0); XCTAssertNotEqual(stateHash(s),stateHash(b))
    }
    func testGridStartsOnTheCourseStartRow() {
        var c=flat(); c.startRow=12
        let s=makeRace(.demo(),course:c)
        XCTAssertTrue(s.runners.allSatisfy { $0.y == 12*ONE && $0.anchorY == 12*ONE })
    }
    func testRaceTimeoutOrdersDNF() throws {
        let c=try CourseLoader.laundryLane(); var s=makeRace(.demo(),course:c)
        s.tick=10799; step(&s,inputs:[],course:c)
        XCTAssertTrue(s.complete); XCTAssertTrue(s.runners.allSatisfy { $0.finished < 0 })
        XCTAssertEqual(s.places.count,6)
    }
}
