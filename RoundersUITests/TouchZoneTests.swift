import XCTest

final class TouchZoneTests: XCTestCase {
    @MainActor func testAutoplayReachesResultsWithSixFinishers() {
        let app=XCUIApplication(); app.launchArguments=["-autoplay","-seed","42"]; app.launch()
        XCTAssertTrue(app.buttons["race.pause"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["results.title"].waitForExistence(timeout:150))
        for name in ["Clem","Bap","Tuppence","Humbug","Bobbin","Pumice"] {
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@",name+" · ")).firstMatch.exists)
        }
        XCTAssertFalse(app.staticTexts["DNF"].exists)
        XCTAssertEqual(app.staticTexts["results.seed"].label,"Seed 42")
        app.buttons["menu.again"].tap()
        XCTAssertTrue(app.buttons["race.pause"].waitForExistence(timeout:3))
    }
    @MainActor func testPointerZonesAfterScrollingAndLandscapeReversal() {
        let app=XCUIApplication(); app.launchArguments=["-uiTest","-inputDebug","-seed","42"]; app.launch()
        let label=app.staticTexts["debug.input"]
        XCTAssertTrue(label.waitForExistence(timeout:15))
        XCTAssertTrue(label.label.contains("mt:true")); XCTAssertTrue(label.label.contains("virtual:ok"))
        func pressZones() {
            let frame=app.windows.firstMatch.frame
            XCTAssertGreaterThan(frame.width,frame.height)
            func press(_ x: CGFloat,_ y: CGFloat,index: Int) {
                func count() -> Int {
                    let counts=(label.label.components(separatedBy:"zoneCounts:").last ?? "").split(separator:",").compactMap { Int($0) }
                    return index < counts.count ? counts[index] : -1
                }
                let before=count()
                app.coordinate(withNormalizedOffset:CGVector(dx:x/frame.width,dy:y/frame.height)).press(forDuration:0.15)
                XCTAssertEqual(count(),before+1,"zone \(index) after camera/orientation change")
            }
            press(frame.width*0.85,frame.height*0.45,index:0); XCTAssertTrue(label.label.contains("seen:hop"))
            press(frame.width*0.15,frame.height*0.45,index:1); XCTAssertTrue(label.label.contains("down"))
            // Both landscape safe areas place the controls within 60...90 pt of the bottom.
            press(200,frame.height-78,index:2); XCTAssertTrue(label.label.contains("handL"))
            press(frame.width-200,frame.height-78,index:3); XCTAssertTrue(label.label.contains("handR"))
        }
        pressZones()
        let nodes=label.label.components(separatedBy:"nodes:").last?.split(separator:" ").first.flatMap { Int($0) } ?? 1000
        XCTAssertLessThan(nodes,300)
        // Move beyond both the first ledge and the initial camera height.
        let tickAdvanced=NSPredicate { _,_ in
            let text=label.label.components(separatedBy:"tick:").last ?? "0"
            return (Int(text.split(separator:" ").first ?? "0") ?? 0) >= 500
        }
        expectation(for:tickAdvanced,evaluatedWith:label)
        waitForExpectations(timeout:25)
        pressZones()
        XCUIDevice.shared.orientation = .landscapeRight
        pressZones()
        app.buttons["race.pause"].tap(); XCTAssertTrue(app.buttons["menu.resume"].waitForExistence(timeout:3))
        app.buttons["menu.resume"].tap(); XCTAssertTrue(app.buttons["race.pause"].waitForExistence(timeout:3))
        app.buttons["race.pause"].tap(); app.buttons["menu.restart"].tap()
        XCTAssertTrue(app.buttons["race.pause"].waitForExistence(timeout:3))
        XCTAssertTrue(label.label.contains("seed:42 "))
        app.buttons["race.pause"].tap(); app.buttons["menu.title"].tap()
        XCTAssertTrue(app.buttons["menu.race"].waitForExistence(timeout:3))
    }
    @MainActor func testRacesWithoutSeedArgumentDrawFreshSeeds() {
        let app=XCUIApplication(); app.launchArguments=["-inputDebug"]; app.launch()
        let label=app.staticTexts["debug.input"]; XCTAssertTrue(label.waitForExistence(timeout:10))
        func seed() -> String { label.label.components(separatedBy:"seed:").last?.split(separator:" ").first.map(String.init) ?? "-" }
        func waitForNewSeed(after old: String) -> String {
            expectation(for:NSPredicate { _,_ in seed() != old },evaluatedWith:label)
            waitForExpectations(timeout:5)
            return seed()
        }
        app.buttons["menu.race"].tap()
        XCTAssertTrue(app.buttons["race.pause"].waitForExistence(timeout:3))
        let first=waitForNewSeed(after:"-")
        app.buttons["race.pause"].tap(); app.buttons["menu.restart"].tap()
        XCTAssertTrue(app.buttons["race.pause"].waitForExistence(timeout:3))
        XCTAssertNotEqual(waitForNewSeed(after:first),first)
    }
    @MainActor func testControllerSnapshotReadPathAndDisconnectSeam() {
        let app=XCUIApplication(); app.launchArguments=["-inputDebug","-seed","42"]; app.launch()
        let label=app.staticTexts["debug.input"]; XCTAssertTrue(label.waitForExistence(timeout:10))
        // selfTest drives every supported button/trigger/stick through GCController,
        // ControllerHub.read and mapPad, plus the last-used disconnect seam.
        XCTAssertTrue(label.label.contains("virtual:ok"))
        app.buttons["menu.difficulty"].tap(); app.buttons["menu.race"].tap()
        XCTAssertTrue(app.buttons["race.pause"].waitForExistence(timeout:3))
    }
}
