/// Hardware-independent keyboard snapshot. Menu arrows must never also confirm.
public struct KeyboardState: Sendable {
    public var space=false, w=false, up=false, s=false, down=false
    public var q=false, e=false, escape=false, p=false, enter=false
    public init() {}
}
public func mapKeyboard(_ k: KeyboardState) -> (bits: UInt8, menu: UInt8) {
    var bits: UInt8=0, menu: UInt8=0
    if k.space || k.w || k.up { bits |= 1 }
    if k.s || k.down { bits |= 2 }
    if k.q { bits |= 4 }; if k.e { bits |= 8 }
    if k.escape || k.p { bits |= 16; menu |= 16 }
    if k.w || k.up { menu |= 1 }
    if k.s || k.down { menu |= 2 }
    if k.space || k.enter { menu |= 4 }
    if k.escape { menu |= 8 }
    return (bits,menu)
}
