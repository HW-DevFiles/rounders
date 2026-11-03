import XCTest
import CryptoKit
@testable import RoundersSim
import RoundersContent
import RoundersInput

func flat(width: Int = 800) -> CourseData {
    var t=[UInt8](repeating:46,count:width*24)
    for x in 0..<width { t[9*width+x]=35 }
    return CourseData(name:"Test",w:width,h:24,finishX:width-2,tiles:t,anchors:[Point(6,10),Point(30,10)])
}
func running(_ x: Int = 6*ONE, y: Int = 10*ONE) -> Runner {
    var r=Runner(); r.x=x; r.y=y; r.vx=Tune.vBase; r.grounded=true; r.anchorX=x; r.anchorY=y; r.stuckX=x; return r
}
final class PhysicsTests: XCTestCase {
    func testHopGolden() {
        let c=flat()
        for (hold,apex,ticks) in [(1,85,21),(3,136,25),(6,203,31),(8,241,35),(10,274,38),(12,301,40)] {
            var r=running(), top=r.y, air=0
            repeat { step(&r,Input(hop:air < hold),air,c); top=max(top,r.y); air += 1 } while !r.grounded && air < 100
            XCTAssertEqual(air,ticks,"hold \(hold)"); XCTAssertEqual((top-10*ONE)*100/ONE,apex,accuracy:1,"hold \(hold)")
            XCTAssertEqual(r.x-6*ONE,Tune.vBase*ticks)
        }
    }
    func testPlonkGolden() {
        let c=flat()
        for (height,normal,plonk) in [(2,15,4),(3,19,6),(5,24,9),(7,29,13)] {
            for slam in [false,true] {
                var r=running(y:(10+height)*ONE); r.grounded=false; r.fallTop=r.y
                var ticks=0
                repeat { step(&r,Input(down:slam),ticks,c); ticks += 1 } while !r.grounded && ticks < 100
                XCTAssertEqual(ticks,slam ? plonk : normal)
                XCTAssertEqual(r.roll,slam ? 36 : 0)
            }
        }
    }
    func testGapAndWallWindows() {
        // Firstmate decision 2026-11-03: accept the inclusive 40-tick gap-2
        // fixture boundary; all other windows and hop/plonk goldens match.
        for (width,want) in [(2,40),(3,33),(4,27),(5,20),(6,13),(7,7),(8,0)] {
            var c=flat()
            for x in 50..<(50+width) { c.t[9*c.w+x]=46 }
            var count=0
            for press in -80...20 {
                // Press offset is measured in 1-tick distances from centre at near edge.
                var r=running(50*ONE-80*Tune.vBase)
                var tick=0
                while r.x < (52+width)*ONE && r.alive && tick < 150 {
                    step(&r,Input(hop:tick >= 80+press),tick,c); tick += 1
                }
                if r.alive && r.y >= 10*ONE && !r.bumpFlag { count += 1 }
            }
            XCTAssertEqual(count,want,"gap \(width)")
        }
        for (height,want) in [(1,34),(2,25),(3,6),(4,0)] {
            var c=flat()
            for x in 50...70 { for y in 10..<(10+height) { c.t[y*c.w+x]=35 } }
            var count=0
            for press in -80...0 {
                var r=running(50*ONE-80*Tune.vBase), tick=0
                while r.x < 53*ONE && r.alive && r.bumps == 0 && tick < 150 { step(&r,Input(hop:tick >= 80+press),tick,c); tick += 1 }
                if r.alive && r.bumps == 0 && r.x >= 53*ONE { count += 1 }
            }
            XCTAssertEqual(count,want,"wall \(height)")
        }
    }
    func testTwoTileGapSamplingBoundary() {
        var c=flat()
        for x in 50..<52 { c.t[9*c.w+x]=46 }
        var counts: [Int]=[]
        for phase in [0, Tune.vBase/4, Tune.vBase/2, Tune.vBase*3/4] {
            var count=0
            for press in -80...20 {
                var r=running(50*ONE-80*Tune.vBase+phase), tick=0
                while r.x < 54*ONE && r.alive && tick < 150 {
                    step(&r,Input(hop:tick >= 80+press),tick,c); tick += 1
                }
                if r.alive && r.y >= 10*ONE && !r.bumpFlag { count += 1 }
            }
            counts.append(count)
        }
        print("Gap-2 sampling phases: \(counts)")
        XCTAssertTrue(counts.allSatisfy { (39...40).contains($0) })
    }
    func testCourseContractAndRecoveryAnchor() throws {
        let c=try CourseLoader.laundryLane()
        let rows=(0..<c.h).reversed().map { row in String(bytes:c.t[(row*c.w)..<((row+1)*c.w)],encoding:.utf8)! }.joined(separator:"\n")
        XCTAssertEqual(SHA256.hash(data:Data(rows.utf8)).map { String(format:"%02x",$0) }.joined(),"5d00e468b8fdbb4bfb3aeebd69025277c8d4203c691767331e24871569f511ab")
        XCTAssertEqual(c.parcels.count,18); XCTAssertEqual(c.anchors.count,23); XCTAssertEqual(c.hazards.count,4)
        XCTAssertTrue(c.anchors.contains(Point(530,10)))
        var r=running(510*ONE); r.anchorX=510*ONE; r.anchorY=10*ONE
        for _ in 0..<3 {
            r.alive=false; r.bonkTimer=66
            for t in 0..<65 { step(&r,Input(),t,c); XCTAssertFalse(r.alive) }
            step(&r,Input(),65,c); XCTAssertTrue(r.alive)
        }
        XCTAssertEqual(r.anchorX >> 16,530); XCTAssertEqual(r.invuln,75); XCTAssertEqual(r.vx,0)
    }
    func testTuckCeilingBufferAndCoyote() {
        var c=flat()
        for x in 10...15 { c.t[11*c.w+x]=35 }
        var r=running(11*ONE); r.tucked=true
        step(&r,Input(hop:true),0,c); XCTAssertTrue(r.tucked); XCTAssertTrue(r.grounded)
        var gap=flat(); for x in 10...15 { gap.t[9*gap.w+x]=46 }
        r=running(10*ONE+ONE/2)
        step(&r,Input(),0,gap); XCTAssertEqual(r.coyote,6)
        for t in 1...5 { step(&r,Input(),t,gap) }
        step(&r,Input(hop:true),6,gap); XCTAssertGreaterThan(r.vy,0)
    }
}
