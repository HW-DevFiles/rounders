import Foundation
import GameController
import RoundersSim
import RoundersInput

@MainActor final class ControllerHub {
    private var known: [ObjectIdentifier: GCController] = [:]
    private var callbackBits: [ObjectIdentifier: UInt8] = [:]
    private var pending: UInt8 = 0
    private var observers: [NSObjectProtocol] = []
    private(set) var lastUsed: ObjectIdentifier?
    var onDisconnect: (() -> Void)?
    var count: Int { GCController.controllers().count }
    init() {
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rescan() }
            })
        }
    }
    nonisolated static func read(_ p: GCExtendedGamepad) -> PadState {
        var s=PadState()
        s.a=p.buttonA.isPressed; s.b=p.buttonB.isPressed; s.x=p.buttonX.isPressed; s.y=p.buttonY.isPressed
        s.l1=p.leftShoulder.isPressed; s.r1=p.rightShoulder.isPressed; s.l2=p.leftTrigger.value; s.r2=p.rightTrigger.value
        s.dpadUp=p.dpad.up.isPressed; s.dpadDown=p.dpad.down.isPressed; s.menu=p.buttonMenu.isPressed; s.stickY=p.leftThumbstick.yAxis.value
        return s
    }
    func rescan() {
        let current=GCController.controllers()
        let ids=current.map { ObjectIdentifier($0) }
        for id in known.keys where !ids.contains(id) { disconnected(id) }
        for controller in current {
            let id=ObjectIdentifier(controller)
            guard known[id] == nil, let p=controller.extendedGamepad else { continue }
            known[id]=controller
            p.valueChangedHandler = { [weak self] pad,_ in
                let snapshot=Self.read(pad)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let bits=mapPad(snapshot).bits
                    self.pending |= bits & ~(self.callbackBits[id] ?? 0)
                    self.callbackBits[id]=bits
                    if bits != 0 { self.lastUsed=id }
                }
            }
        }
    }
    /// Test seam: simulator's permanent virtual pad cannot exercise real disconnects.
    func disconnected(_ id: ObjectIdentifier) {
        known[id]?.extendedGamepad?.valueChangedHandler=nil
        known[id]=nil; callbackBits[id]=nil
        if lastUsed == id { lastUsed=nil; pending=0; onDisconnect?() }
    }
    func poll() -> (bits: UInt8, edges: UInt8, up: Bool, down: Bool, back: Bool) {
        rescan()
        var bits: UInt8=0, up=false, down=false, back=false
        for g in GCController.controllers() {
            guard let p=g.extendedGamepad else { continue }
            let s=Self.read(p), b=mapPad(s).bits
            bits |= b; up = up || s.dpadUp || s.stickY > 0.5; down = down || s.dpadDown || s.stickY < -0.5; back = back || s.b
            if b != 0 || up || down { lastUsed=ObjectIdentifier(g) }
        }
        let edges=pending; pending=0
        return (bits,edges,up,down,back)
    }
    func selfTest() -> Bool {
        let v=GCController.withExtendedGamepad()
        guard let p=v.extendedGamepad else { return false }
        let checks: [(GCControllerButtonInput,UInt8)] = [(p.buttonA,1),(p.buttonB,2),(p.leftShoulder,4),(p.rightShoulder,8),(p.leftTrigger,4),(p.rightTrigger,8),(p.buttonY,16),(p.buttonMenu,16)]
        for (button,bit) in checks {
            button.setValue(1)
            guard mapPad(Self.read(p)).bits & bit != 0 else { return false }
            button.setValue(0)
        }
        // Direction buttons derive from their parent's axes; setting the down
        // button alone does not change a snapshot direction pad.
        p.dpad.setValueForXAxis(0,yAxis:-1)
        guard mapPad(Self.read(p)).has(2) else { return false }
        p.dpad.setValueForXAxis(0,yAxis:0)
        p.leftThumbstick.setValueForXAxis(0,yAxis:-1)
        guard mapPad(Self.read(p)).has(2) else { return false }
        p.leftThumbstick.setValueForXAxis(0,yAxis:0)
        let fake=ObjectIdentifier(v); known[fake]=v; lastUsed=fake
        var noticed=false; let previous=onDisconnect
        onDisconnect={ noticed=true }; disconnected(fake); onDisconnect=previous
        return noticed
    }
}

@MainActor func keyboard() -> (bits: UInt8, up: Bool, down: Bool, back: Bool) {
    guard let k=GCKeyboard.coalesced?.keyboardInput else { return (0,false,false,false) }
    func on(_ c: GCKeyCode) -> Bool { k.button(forKeyCode:c)?.isPressed ?? false }
    var b: UInt8=0
    if on(.spacebar) || on(.keyW) || on(.upArrow) { b |= 1 }
    if on(.keyS) || on(.downArrow) { b |= 2 }
    if on(.keyQ) { b |= 4 }; if on(.keyE) { b |= 8 }
    if on(.escape) || on(.keyP) { b |= 16 }
    return (b,on(.upArrow) || on(.keyW),on(.downArrow) || on(.keyS),on(.escape))
}
