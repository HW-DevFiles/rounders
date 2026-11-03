public struct Point: Sendable, Equatable {
 public var x: Int; public var y: Int
 public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}
public struct Hazard: Sendable {
 public var x0, x1, y0, y1, period, on, phase: Int
 public var kind: String
 public init(x0: Int, x1: Int, y0: Int, y1: Int, period: Int, on: Int, phase: Int, kind: String) {
  self.x0=x0; self.x1=x1; self.y0=y0; self.y1=y1; self.period=period; self.on=on; self.phase=phase; self.kind=kind
 }
}
public struct Band: Sendable {
 public var x0, x1, yMin, yMax: Int
 public init(_ a: Int, _ b: Int, _ c: Int, _ d: Int) { x0=a; x1=b; yMin=c; yMax=d }
}
public struct Entry: Sendable { public var x: Int; public var plan: Plan
 public init(x: Int, plan: Plan) { self.x=x; self.plan=plan }
}
public struct Route: Sendable {
 public var name: String; public var bands: [Band]; public var entries: [Entry]
 public var deltaCs, risk, parcelDelta: Int
 public init(name: String, bands: [Band], entries: [Entry], deltaCs: Int, risk: Int, parcelDelta: Int) {
 self.name=name; self.bands=bands; self.entries=entries; self.deltaCs=deltaCs; self.risk=risk; self.parcelDelta=parcelDelta
 }
}
public struct Fork: Sendable {
 public var name: String; public var x0, x1: Int; public var routes: [Route]
 public init(name: String, x0: Int, x1: Int, routes: [Route]) { self.name=name; self.x0=x0; self.x1=x1; self.routes=routes }
}
public struct CourseData: Sendable {
 public var name: String; public var w, h, finishX, startRow: Int
 public var t: [UInt8]; public var hazards: [Hazard]; public var forks: [Fork]
 public var parcels, anchors: [Point]; public var chokepoints: [Int]
 public init(name: String, w: Int, h: Int, finishX: Int, startRow: Int, tiles: [UInt8], hazards: [Hazard] = [], forks: [Fork] = [], parcels: [Point] = [], anchors: [Point] = [], chokepoints: [Int] = []) {
 self.name=name; self.w=w; self.h=h; self.finishX=finishX; self.startRow=startRow; t=tiles; self.hazards=hazards; self.forks=forks; self.parcels=parcels; self.anchors=anchors; self.chokepoints=chokepoints
 }
 @inline(__always) public func at(_ c: Int, _ r: Int) -> UInt8 {
 if c < 0 || c >= w { return 35 }; if r < 0 || r >= h { return 46 }; return t[r*w+c]
 }
}
