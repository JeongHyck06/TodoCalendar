import XCTest
import UIKit

final class TodoCalendarUITests: XCTestCase {
    @MainActor func testCalendarAndTodoFlow() throws {
        let app = XCUIApplication()
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["addTodo"].waitForExistence(timeout: 15))
        let baseline = XCTAttachment(screenshot: app.screenshot())
        baseline.name = "Calendar baseline"
        baseline.lifetime = .keepAlways
        add(baseline)

        if app.segmentedControls["categoryFilter"].exists {
            app.segmentedControls["categoryFilter"].buttons["학교 시험"].tap()
            XCTAssertTrue(app.buttons["todo-중간고사 · 수학"].exists)
            XCTAssertFalse(app.buttons["todo-정기 합주"].exists)
            app.segmentedControls["categoryFilter"].buttons["전체"].tap()
        }

        app.buttons["addTodo"].tap()
        let title = app.textFields["todoTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveTodo"].isEnabled)
        title.tap()
        title.typeText("UI 테스트 일정")
        let editor = XCTAttachment(screenshot: app.screenshot())
        editor.name = "Todo editor"
        editor.lifetime = .keepAlways
        add(editor)
        app.buttons["saveTodo"].tap()
        let row = app.buttons["todo-UI 테스트 일정"].firstMatch
        if !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let complete = app.buttons["complete-UI 테스트 일정"].firstMatch
        complete.tap()
        XCTAssertTrue(complete.label.contains("완료 취소"))

        row.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(" 수정")
        app.buttons["saveTodo"].tap()
        let edited = app.buttons["todo-UI 테스트 일정 수정"].firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: 5))
        edited.tap()
        let delete = app.buttons["투두 삭제"].firstMatch
        if !delete.isHittable { app.swipeUp() }
        delete.tap()
        app.buttons.matching(identifier: "투두 삭제").allElementsBoundByIndex.last!.tap()
        XCTAssertFalse(edited.waitForExistence(timeout: 2))

        app.buttons["nextMonth"].tap()
        XCTAssertTrue(app.staticTexts["11월"].exists || app.staticTexts["2026년 11월"].exists)
        app.buttons["previousMonth"].tap()
        XCTAssertTrue(app.buttons["day-2026-10-02"].exists)
    }
}
