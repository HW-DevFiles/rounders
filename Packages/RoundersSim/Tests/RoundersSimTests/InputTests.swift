import XCTest
import RoundersSim
import RoundersInput

final class InputTests: XCTestCase {
    func testEveryPadMapping() {
        var p=PadState(); XCTAssertEqual(mapPad(p).bits,0)
        p.a=true; XCTAssertEqual(mapPad(p).bits,1); p.a=false
        p.b=true; XCTAssertEqual(mapPad(p).bits,2); p.b=false
        p.dpadDown=true; XCTAssertEqual(mapPad(p).bits,2); p.dpadDown=false
        p.stickY = -0.5; XCTAssertEqual(mapPad(p).bits,0); p.stickY = -0.51; XCTAssertEqual(mapPad(p).bits,2); p.stickY=0
        p.l1=true; XCTAssertEqual(mapPad(p).bits,4); p.l1=false
        p.r1=true; XCTAssertEqual(mapPad(p).bits,8); p.r1=false
        p.l2=0.3; XCTAssertEqual(mapPad(p).bits,0); p.l2=0.31; XCTAssertEqual(mapPad(p).bits,4); p.l2=0
        p.r2=0.31; XCTAssertEqual(mapPad(p).bits,8); p.r2=0
        p.y=true; XCTAssertEqual(mapPad(p).bits,16); p.y=false
        p.menu=true; XCTAssertEqual(mapPad(p).bits,16); p.menu=false
        p.x=true; p.dpadUp=true; XCTAssertEqual(mapPad(p).bits,0)
    }
    func testShortTapPersistsAcrossZeroTickFramesAndNotCatchup() {
        var latch=InputLatch(), clock=TickClock()
        XCTAssertEqual(clock.advance(0,running:true),0)
        latch.sample(1); XCTAssertEqual(clock.advance(1.0/120,running:true),0)
        latch.sample(0); XCTAssertEqual(clock.advance(1.0/60,running:true),1)
        XCTAssertEqual(latch.consume().bits,1)
        XCTAssertEqual(clock.advance(0.2,running:true),5)
        for _ in 0..<5 { XCTAssertEqual(latch.consume().bits,0) }
        latch.sample(0,capturedEdges:4); XCTAssertEqual(latch.consume().bits,4); XCTAssertEqual(latch.consume().bits,0)
    }
    func testHeldMovementAndHandsDoNotRepeat() {
        var latch=InputLatch(); latch.sample(1|2|4|8)
        XCTAssertEqual(latch.consume().bits,15)
        for _ in 0..<5 { XCTAssertEqual(latch.consume().bits,3) }
        latch.sample(0); _=latch.consume(); latch.sample(4); XCTAssertEqual(latch.consume().bits,4)
    }
    func testTransitionsSuppressHeldUntilReleasedAndBoundDebt() {
        var latch=InputLatch(); latch.sample(1); latch.reset(suppressing:1)
        latch.sample(1); XCTAssertEqual(latch.consume().bits,0)
        latch.sample(0); latch.sample(1); XCTAssertEqual(latch.consume().bits,1)
        var clock=TickClock(); XCTAssertEqual(clock.advance(0,running:true),0)
        for time in [1.0,10,100,1000] { XCTAssertEqual(clock.advance(time,running:true),5); XCTAssertLessThanOrEqual(clock.alpha,1) }
        XCTAssertEqual(clock.advance(2000,running:false),0); clock.reset(); XCTAssertEqual(clock.advance(3000,running:true),0)
        XCTAssertEqual(clock.advance(3000+1.0/60,running:true),1)
    }
}
