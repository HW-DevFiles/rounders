import XCTest

final class TouchZoneTests: XCTestCase {
    @MainActor func testPointerZonesAfterScrollingAndLandscapeReversal() {
        let app=XCUIApplication(); app.launchArguments=["-uiTest","-inputDebug","-seed","42"]; app.launch()
        let label=app.staticTexts["debug.input"]
        XCTAssertTrue(label.waitForExistence(timeout:15))
        XCTAssertTrue(label.label.contains("mt:true")); XCTAssertTrue(label.label.contains("virtual:ok"))
        func pressZones() {
            let frame=app.windows.firstMatch.frame
            XCTAssertGreaterThan(frame.width,frame.height)
            func press(_ x: CGFloat,_ y: CGFloat) { app.coordinate(withNormalizedOffset:CGVector(dx:x/frame.width,dy:y/frame.height)).press(forDuration:0.15) }
            press(frame.width*0.85,frame.height*0.45); XCTAssertTrue(label.label.contains("seen:hop"))
            press(frame.width*0.15,frame.height*0.45); XCTAssertTrue(label.label.contains("down"))
            // Both landscape safe areas place the controls within 60...90 pt of the bottom.
            press(200,frame.height-78); XCTAssertTrue(label.label.contains("handL"))
            press(frame.width-200,frame.height-78); XCTAssertTrue(label.label.contains("handR"))
        }
        pressZones()
        // Move beyond both the first ledge and the initial camera height.
        let tickAdvanced=NSPredicate { _,_ in
            let text=label.label.components(separatedBy:"tick:").last ?? "0"
            return (Int(text) ?? 0) >= 500
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
        app.buttons["race.pause"].tap(); app.buttons["menu.title"].tap()
        XCTAssertTrue(app.buttons["menu.race"].waitForExistence(timeout:3))
    }
    @MainActor func testControllerSnapshotReadPathAndDisconnectSeam() {
        let app=XCUIApplication(); app.launchArguments=["-inputDebug"]; app.launch()
        let label=app.staticTexts["debug.input"]; XCTAssertTrue(label.waitForExistence(timeout:10))
        // selfTest drives every supported button/trigger/stick through GCController,
        // ControllerHub.read and mapPad, plus the last-used disconnect seam.
        XCTAssertTrue(label.label.contains("virtual:ok"))
        app.buttons["menu.difficulty"].tap(); app.buttons["menu.race"].tap()
        XCTAssertTrue(app.buttons["race.pause"].waitForExistence(timeout:3))
    }
}
