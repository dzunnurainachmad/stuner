import XCTest

final class stunerUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Reset persisted state so tests always start with Standard tuning / A4=440
        app.launchArguments += ["-selectedTuningId", "", "-a4Frequency", "0"]
        app.launch()
    }

    // MARK: - Screen Elements

    @MainActor
    func testTunerScreenLoads() throws {
        // Header shows tuning name and A4 frequency
        let header = app.staticTexts["headerLabel"]
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        XCTAssertTrue(header.label.contains("Standard"))
        XCTAssertTrue(header.label.contains("440"))

        // Detected note placeholder
        let note = app.staticTexts["detectedNote"]
        XCTAssertTrue(note.exists)
        XCTAssertEqual(note.label, "—")

        // Frequency label placeholder
        let freq = app.staticTexts["frequencyLabel"]
        XCTAssertTrue(freq.exists)
        XCTAssertEqual(freq.label, "—")
    }

    @MainActor
    func testAutoManualToggle() throws {
        let autoButton = app.buttons["autoButton"]
        let manualButton = app.buttons["manualButton"]

        XCTAssertTrue(autoButton.waitForExistence(timeout: 3))
        XCTAssertTrue(manualButton.exists)

        // Tap Manual
        manualButton.tap()

        // Tap Auto
        autoButton.tap()
    }

    @MainActor
    func testStringButtonsExist() throws {
        // Standard tuning: E2, A2, D3, G3, B3, E4
        let stringNames = ["E2", "A2", "D3", "G3", "B3", "E4"]
        for name in stringNames {
            let button = app.buttons["string_\(name)"]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "String button \(name) should exist")
        }
    }

    @MainActor
    func testTapStringSelectsIt() throws {
        // Tap G3 string
        let g3Button = app.buttons["string_G3"]
        XCTAssertTrue(g3Button.waitForExistence(timeout: 3))
        g3Button.tap()

        // Tap again to deselect (back to auto)
        g3Button.tap()
    }

    @MainActor
    func testTapMultipleStrings() throws {
        let e2 = app.buttons["string_E2"]
        let a2 = app.buttons["string_A2"]
        let e4 = app.buttons["string_E4"]

        XCTAssertTrue(e2.waitForExistence(timeout: 3))

        // Tap through strings
        e2.tap()
        a2.tap()
        e4.tap()

        // Deselect
        e4.tap()
    }

    // MARK: - Control Buttons

    @MainActor
    func testToneButtonExists() throws {
        let toneButton = app.buttons["toneButton"]
        XCTAssertTrue(toneButton.waitForExistence(timeout: 3))
    }

    @MainActor
    func testToneButtonToggle() throws {
        let toneButton = app.buttons["toneButton"]
        XCTAssertTrue(toneButton.waitForExistence(timeout: 3))

        // Tap to start tone
        toneButton.tap()

        // Tap to stop tone
        toneButton.tap()
    }

    @MainActor
    func testTuningButtonOpensSheet() throws {
        let tuningButton = app.buttons["tuningButton"]
        XCTAssertTrue(tuningButton.waitForExistence(timeout: 3))

        tuningButton.tap()

        // Verify tuning picker sheet appears with tuning names
        let standard = app.staticTexts["Standard"]
        XCTAssertTrue(standard.waitForExistence(timeout: 3), "Tuning picker should show Standard tuning")

        let dropD = app.staticTexts["Drop D"]
        XCTAssertTrue(dropD.exists, "Tuning picker should show Drop D")

        // Dismiss sheet by swiping down
        app.swipeDown()
    }

    @MainActor
    func testSettingsButtonOpensSheet() throws {
        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))

        settingsButton.tap()

        // Verify settings sheet appears - look for A4 reference text
        let settingsContent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'A4'"))
        XCTAssertTrue(settingsContent.firstMatch.waitForExistence(timeout: 3), "Settings should show A4 reference")

        // Dismiss
        app.swipeDown()
    }

    @MainActor
    func testSelectTuningFromPicker() throws {
        let tuningButton = app.buttons["tuningButton"]
        XCTAssertTrue(tuningButton.waitForExistence(timeout: 3))
        tuningButton.tap()

        // Select Drop D
        let dropD = app.staticTexts["Drop D"]
        XCTAssertTrue(dropD.waitForExistence(timeout: 3))
        dropD.tap()

        // Dismiss sheet
        app.swipeDown()
        sleep(1)

        // Verify header updated
        let header = app.staticTexts["headerLabel"]
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        XCTAssertTrue(header.label.contains("Drop D"))

        // Verify string buttons updated - Drop D has D2 instead of E2
        let d2Button = app.buttons["string_D2"]
        XCTAssertTrue(d2Button.waitForExistence(timeout: 3), "Drop D should show D2 string")
    }

    @MainActor
    func testManualModeThenSelectString() throws {
        let manualButton = app.buttons["manualButton"]
        XCTAssertTrue(manualButton.waitForExistence(timeout: 3))
        manualButton.tap()

        // Select A2 string
        let a2 = app.buttons["string_A2"]
        XCTAssertTrue(a2.waitForExistence(timeout: 3))
        a2.tap()

        // Switch back to auto
        let autoButton = app.buttons["autoButton"]
        autoButton.tap()
    }
}
