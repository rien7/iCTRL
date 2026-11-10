var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() {
        print("FAIL after \(checks) checks: \(message)")
        exit(1)
    }
}
func entry(_ text: String, _ type: String = "StaticText") -> ActionHandler.ScreenText {
    .init(text: text, type: type, frame: CGRect(x: 100, y: 300, width: 180, height: 60))
}
func point(_ x: Double, _ y: Double) -> JSONValue { .object(["x": .double(x), "y": .double(y)]) }
let captcha = [entry("slide to verify"), entry("滑块", "Button"), entry("关闭", "Button")]

// Real observations still classify the challenge and keep useful response data.
let handler = ActionHandler()
let observation = handler.observe(captcha)
check(observation["blocked_by"] == .string("captcha"), "CAPTCHA detection was hidden")
check(observation["close_candidates"]?.toAny() is [Any], "Close candidates were lost")
check(observation["hint"]!.stringValue!.contains("existing read hint"), "Existing hint was overwritten")
let detected = ActionHandler.blockers(captcha)
check(detected.area?.contains(CGPoint(x: 150, y: 320)) == true, "Challenge area changed")

// Exercise starts inside the observed area, a default origin, reference
// endpoints and a path crossing from outside, all without special flags.
let gestures: [(String, [String: JSONValue])] = [
    ("tap", ["x": .int(150), "y": .int(320)]),
    ("swipe", ["x": .int(150), "y": .int(320), "direction": .string("right")]),
    ("swipe", ["direction": .string("right")]),
    ("scroll", ["x": .int(150), "y": .int(320), "direction": .string("right")]),
    ("drag", ["from_x": .int(150), "from_y": .int(320), "to_x": .int(250), "to_y": .int(320)]),
    ("drag", ["points": .array([point(20, 200), point(150, 320), point(250, 320)])]),
    ("drag", ["from_ref": .string("slider"), "to_ref": .string("end")]),
]
for (method, params) in gestures {
    let before = handler.calls.count
    let (result, error) = handler.dispatch(method: method, params: params)
    check(error == nil && result?["executed"] == .string(method), "\(method) refused after CAPTCHA observation")
    check(handler.calls.count == before + 1, "\(method) skipped or repeated the execution boundary")
    check(handler.calls.last!.cmd.name == method, "Method changed before execution")
    if let points = params["points"] {
        check(handler.calls.last!.cmd.dragPathParams?["points"] == points, "Path changed before execution")
    }
}
for _ in 0..<3 { _ = handler.observe(captcha) }
check(!handler.observe(captcha)["hint"]!.stringValue!.contains("stop using"), "Repeated reads imposed a CAPTCHA policy")
handler.executionError = .serverError("ordinary execution failure")
let (_, executionError) = handler.dispatch(method: "swipe", params: gestures[1].1)
check(executionError?.message == "ordinary execution failure", "Normal execution errors were hidden")

// CAPTCHA metadata must not bypass the dispatcher's unrelated preflight guards.
let guarded = ActionHandler()
_ = guarded.observe(captcha)
guarded.hasSystemAlert = true
let (_, alertError) = guarded.dispatch(method: "tap", params: ["ref": .string("app-button")])
check(alertError?.code == -32000 && guarded.calls.isEmpty, "System-alert preflight was bypassed")
guarded.refStore["alert-button"] = .init(bundleId: "com.apple.springboard")
guarded.refAlertTitle["alert-button"] = "Old permission"
let (_, staleError) = guarded.dispatch(method: "tap", params: ["ref": .string("alert-button")])
check(staleError?.code == -32602 && guarded.calls.isEmpty, "Changed-alert ref protection was bypassed")
guarded.hasSystemAlert = false
let (_, typeError) = guarded.dispatch(method: "tap", params: ["element_type": .string("invalid")])
check(typeError?.code == -32602 && guarded.calls.isEmpty, "Unknown element-type preflight was bypassed")
check(guarded.checkCoordinate(CGPoint(x: -1, y: 320))?.code == -32602, "Coordinate bounds were bypassed")
let (invalidPath, pathError) = ContinuousDragPath.parse(["points": .array([point(150, 320), point(500, 320)])]) {
    guarded.checkCoordinate($0, index: $1)
}
check(invalidPath == nil && pathError?.code == -32602, "Path bounds were bypassed")

let throttled = ActionHandler()
let rateEntries = [entry("too many requests"), entry("Close", "Button")]
for _ in 0..<3 { _ = throttled.observe(rateEntries) }
let rate = throttled.observe(rateEntries)
check(rate["blocked_by"] == .string("rate_limit"), "Rate-limit detection changed")
check(rate["hint"]!.stringValue!.contains("wait at least a minute"), "Rate-limit backoff advice changed")
check(rate["hint"]!.stringValue!.contains("stop using it for now"), "Repeated rate-limit advice changed")
check(ActionHandler.blockers([entry("Unrelated ordinary content")]).kind == nil, "Ordinary text misclassified")
check(throttled.observe([entry("领取"), entry("关闭")], overlay: true)["promo_popup"] == .bool(true), "Promo advice changed")

// Real pairing/authentication/crypto, with in-memory persistence and no network.
final class Approval: AuthManagerDelegate {
    var answer: ((Bool) -> Void)?
    func authManager(_ manager: AuthManager, didReceiveAuthRequest clientName: String,
                     requestID: String, nearby: Bool, fingerprint: String?, completion: @escaping (Bool) -> Void) {
        answer = completion
    }
    func authManager(_ manager: AuthManager, didExpireAuthRequest clientName: String, requestID: String) {}
}
let auth = AuthManager.shared
let approval = Approval()
auth.delegate = approval
var remoteOutcome: PairOutcome?
auth.requestAuth(clientName: "fixture-remote", nearby: false) { remoteOutcome = $0 }
check(remoteOutcome == nil && approval.answer != nil, "Pairing did not wait for approval")
check(auth.activeSessions.isEmpty, "Pending pairing granted access")
var busyOutcome: PairOutcome?
auth.requestAuth(clientName: "fixture-remote-2", nearby: false) { busyOutcome = $0 }
if case .busy? = busyOutcome {} else { check(false, "Pending-pair protection lost") }
approval.answer?(false)
if case .denied? = remoteOutcome {} else { check(false, "Denied pairing accepted") }
check(auth.activeSessions.isEmpty, "Denied pairing granted access")
var cooldownOutcome: PairOutcome?
auth.requestAuth(clientName: "fixture-remote-3", nearby: false) { cooldownOutcome = $0 }
if case .coolingDown? = cooldownOutcome {} else { check(false, "Pairing cooldown lost") }
var localOutcome: PairOutcome?
auth.requestAuth(clientName: "fixture-local", nearby: false, local: true) { localOutcome = $0 }
check(localOutcome == nil, "Local pairing did not wait for approval")
approval.answer?(true)
guard case .approved(let session)? = localOutcome, let key = session.key else {
    fatalError("Independent local pairing slot failed")
}

func envelope(nonceByte: UInt8, timestamp: Int = Int(Date().timeIntervalSince1970)) -> [String: Any] {
    let nonce = Data(repeating: nonceByte, count: 16)
    let plaintext = Data("{\"jsonrpc\":\"2.0\",\"method\":\"tap\",\"id\":1}".utf8)
    let encKey = SecureEnvelope.hmac(key, Data(SecureEnvelope.labelEncRequest.utf8) + nonce)
    let ciphertext = SecureEnvelope.keystreamXOR(key: encKey, nonce: nonce, data: plaintext)
    let macKey = SecureEnvelope.hmac(key, Data(SecureEnvelope.labelMac.utf8) + nonce)
    let signed = Data("v1".utf8) + Data(hexString: session.id)! + SecureEnvelope.be64(UInt64(timestamp)) + nonce + ciphertext
    return ["v": 1, "tok": session.id, "ts": timestamp, "nonce": nonce.hexString,
            "ct": ciphertext.base64EncodedString(), "tag": SecureEnvelope.hmac(macKey, signed).hexString]
}
func rejectedEnvelope(_ value: [String: Any], code: String) {
    do {
        _ = try auth.openEnvelope(value)
        check(false, "Invalid envelope accepted (expected \(code))")
    } catch let error as SecureEnvelope.Failure {
        check(error.code == code, "Unexpected auth error: \(error.code), expected \(code)")
    } catch { check(false, "Unexpected error: \(error)") }
}
let validEnvelope = envelope(nonceByte: 1)
let opened = try auth.openEnvelope(validEnvelope)
check(opened.plaintext.contains("\"method\":\"tap\""), "Valid sealed request failed")
check(opened.seal("{}").contains("\"ct\""), "Response was not sealed")
rejectedEnvelope(validEnvelope, code: "nonce_replayed")
var tampered = envelope(nonceByte: 2)
tampered["tag"] = String(repeating: "00", count: 32)
rejectedEnvelope(tampered, code: "bad_tag")
let afterTamper = try auth.openEnvelope(envelope(nonceByte: 2))
check(afterTamper.plaintext.contains("tap"), "Bad MAC poisoned nonce cache")
rejectedEnvelope(envelope(nonceByte: 3, timestamp: Int(Date().timeIntervalSince1970) - 300), code: "ts_skew")
var unknown = envelope(nonceByte: 4)
unknown["tok"] = session.id == "ffffffff" ? "00000000" : "ffffffff"
rejectedEnvelope(unknown, code: "auth_failed")
check(!SecureEnvelope.looksLikeEnvelope(["method": "tap"]), "Plaintext request accepted as envelope")
print("ActionDispatch: \(checks) behavior checks passed (real dispatch/detection/auth; device I/O is stubbed)")
