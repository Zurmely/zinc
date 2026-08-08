import XCTest
@testable import ZincCore

final class DoubleShiftTriggerPolicyTests: XCTestCase {
    func testSuppressesWhenZincIsFrontmost() {
        XCTAssertTrue(
            DoubleShiftTriggerPolicy.shouldSuppress(
                frontmostBundleID: "com.example.Zinc",
                zincBundleID: "com.example.Zinc",
                excludedBundleIDs: []
            )
        )
    }

    func testDoesNotSuppressZincBasedOnExclusionList() {
        XCTAssertTrue(
            DoubleShiftTriggerPolicy.shouldSuppress(
                frontmostBundleID: "com.example.Zinc",
                zincBundleID: "com.example.Zinc",
                excludedBundleIDs: ["com.other.App"]
            )
        )
    }

    func testSuppressesListedApps() {
        XCTAssertTrue(
            DoubleShiftTriggerPolicy.shouldSuppress(
                frontmostBundleID: "com.other.App",
                zincBundleID: "com.example.Zinc",
                excludedBundleIDs: ["com.other.App"]
            )
        )
    }

    func testDoesNotSuppressUnlistedApps() {
        XCTAssertFalse(
            DoubleShiftTriggerPolicy.shouldSuppress(
                frontmostBundleID: "com.other.App",
                zincBundleID: "com.example.Zinc",
                excludedBundleIDs: []
            )
        )
    }

    func testDoesNotSuppressWhenFrontmostUnknown() {
        XCTAssertFalse(
            DoubleShiftTriggerPolicy.shouldSuppress(
                frontmostBundleID: nil,
                zincBundleID: "com.example.Zinc",
                excludedBundleIDs: []
            )
        )
    }
}
