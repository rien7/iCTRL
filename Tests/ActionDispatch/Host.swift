// Host-only doubles for dependencies of the real ActionHandler.dispatch.
// No listener, keychain, persisted tokens, screenshot or touch injection.
import Foundation
import CoreGraphics

enum TokenFileStore {
    static var data: Data?
    static func load() -> Data? { data }
    static func save(_ value: Data) { data = value }
}
enum KeychainStore { static func load() -> Data? { nil } }
struct UIImage {}
enum ForegroundApp { static func frontmostPID() -> pid_t { 1 } }
enum iCTRLUITests {
    final class Buffer { func append(_ message: String) {} }
    static let logBuffer = Buffer()
    static func captureFrame() -> UIImage? { nil }
}

// Settling is not the subject of this regression. These deterministic values
// allow the *whole* dispatcher (not a reimplementation of its gates) to compile.
enum ScreenSettle {
    struct Frame {}
    struct Patch {}
    struct Observation {
        var stable = true
        var changed: Bool? = nil
        var nearTap = false
        var last: Frame?
        var newScreen = false
        var motion = false
        var waitedMs = 0
        var samples = 0
        var lastDiff = 0.0
        var firstChangeMs: Int?
        var json: JSONValue { .object([:]) }
    }
    static let quietWindow = 0.1
    static let quietWindowForControls = 0.2
    static let newScreenWatch = 0.1
    static let scrolledShare = 0.1
    static func sample() -> Frame? { nil }
    static func frame(from image: UIImage) -> Frame? { nil }
    static func changedCells(_ a: Frame, _ b: Frame) -> [Bool] { [false] }
    static func cells(covering: [CGRect], screen: CGSize) -> [Bool] { [false] }
    static func wait(baseline: Frame?, budget: Double, quiet: Double, focus: CGPoint?,
                     screen: CGSize, newScreenWatch: Double, ignore: [Bool]?) -> Observation { Observation() }
    static func patch(from image: UIImage, in area: CGRect, screen: CGSize) -> Patch? { nil }
    static func patchChanged(_ a: Patch, _ b: Patch) -> Bool { false }
    static func contentDiff(_ a: Frame, _ b: Frame) -> Double { 0 }
    static func diff(_ a: Frame, _ b: Frame) -> Double { 0 }
}

final class ActionHandler {
    // PRODUCTION_MEMBERS

    struct ElementRef { let bundleId: String? }
    struct PageCheck {
        let same: Bool
        let why: String
        var json: JSONValue { .object([:]) }
    }
    final class TouchState { var lastTouchPoint: CGPoint? }
    let fastHandler = TouchState()
    var readFrame: ScreenSettle.Frame?
    var tapTargetFrame: CGRect?
    var pageKeyboardTop: Double?
    var refStore: [String: ElementRef] = [:]
    var refAlertTitle: [String: String] = [:]
    let pointSize = CGRect(x: 0, y: 0, width: 390, height: 844)
    let scale = 3.0
    var nowMonotonic = 1000.0
    var foreground = "local.fixture"
    var hasSystemAlert = false
    var currentAlert: String? = "Permission"
    var springboardPID: pid_t = 2
    var readLaps: [String] = []
    var lateReactQuiet: [String: Double] = [:]
    var lateLoaderWatch: [String: Double] = [:]
    var lastSeen: (frame: ScreenSettle.Frame, pid: pid_t, at: TimeInterval)?
    var lastNoChange: (bid: String, frame: ScreenSettle.Frame, at: TimeInterval, base: Double)?
    var lastSettle: (bid: String, frame: ScreenSettle.Frame, at: TimeInterval)?
    var alertWatchUntil = 0.0
    var calls: [(method: String, cmd: ActionCommand)] = []
    var executionError: JSONRPCError?

    static func typeFilterRaws(_ type: String) -> [NSNumber]? { type == "invalid" ? [] : nil }
    func resolveForegroundBundleId() -> String? { foreground }
    func systemAlertUp(precise: Bool = false) -> Bool { hasSystemAlert }
    func systemAlertBlocks() -> JSONRPCError? {
        hasSystemAlert ? .serverError("fixture system alert covers the app") : nil
    }
    func alertTitle() -> String? { currentAlert }
    func samePageCheck(before: ScreenSettle.Frame?, typing: Bool) -> PageCheck? { nil }
    func pipWindowFrame() -> CGRect? { nil }
    func fineLookArea(point: CGPoint, element: CGRect?) -> CGRect { .zero }
    func noteSeen(_ frame: ScreenSettle.Frame) {}
    func coveringLayer() -> String? { nil }
    func flagAlert(_ data: inout [String: JSONValue]) { data["system_alert"] = .bool(true) }
    func timedAlertCheck() -> Bool { hasSystemAlert }

    // The shared execution boundary is a spy: tests assert that the actual
    // public dispatcher reaches it once, with the original parsed command.
    func dispatchInner(method: String, cmd: ActionCommand) -> ([String: JSONValue]?, JSONRPCError?) {
        calls.append((method, cmd))
        if let error = executionError { return (nil, error) }
        return (["executed": .string(method)], nil)
    }
    func observe(_ entries: [ScreenText], overlay: Bool = false) -> [String: JSONValue] {
        var result: [String: JSONValue] = ["hint": .string("existing read hint")]
        flagBlockers(entries, bid: foreground, overlayShown: overlay, into: &result)
        return result
    }
    func checkCoordinate(_ point: CGPoint, index: Int = 0) -> JSONRPCError? {
        validateCoordinate(x: point.x, y: point.y, context: "drag point \(index)")
    }
}
