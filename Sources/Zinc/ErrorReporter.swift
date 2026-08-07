import Foundation

/// Logs Zinc failures and optionally presents a user-visible HUD.
enum ErrorReporter {
    static func report(
        _ error: ZincError,
        presentHUD: Bool = true,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(error, file: file, line: line)
        guard presentHUD else { return }
        SaveHUD.showError(error)
    }

    static func log(
        _ error: ZincError,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        NSLog("Zinc: %@ [%@:%u]", error.localizedDescription, "\(file)", line)
    }
}
