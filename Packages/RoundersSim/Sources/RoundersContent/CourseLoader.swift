import Foundation
import RoundersSim

public enum CourseError: Error { case invalid(String) }
public enum CourseLoader {
    public static func laundryLane() throws -> CourseData {
        guard let url = Bundle.module.url(forResource: "laundry_lane", withExtension: "json") else {
            throw CourseError.invalid("Missing Laundry Lane resource")
        }
        return try load(Data(contentsOf: url))
    }
    public static func load(_ data: Data) throws -> CourseData {
        let d = try JSONDecoder().decode(Document.self, from: data)
        func require(_ valid: Bool, _ message: String) throws { if !valid { throw CourseError.invalid(message) } }
        try require(d.format == 1 && d.width > 0 && d.height > 3 && d.finishX > 0 && d.finishX < d.width && d.startRow > 0 && d.startRow < d.height-2, "Invalid dimensions/version")
        try require(d.rows.count == d.height && d.rows.allSatisfy { $0.utf8.count == d.width }, "Invalid rows")
        let allowed = Array(".#=-><^vSHP".utf8)
        try require(d.rows.allSatisfy { $0.utf8.allSatisfy { allowed.contains($0) } }, "Unknown tile")
        var parcels: [Point] = []
        let tiles = d.rows.reversed().flatMap { Array($0.utf8) }
        for x in 0..<d.width { for y in 0..<d.height where tiles[y*d.width+x] == 80 { parcels.append(Point(x,y)) } }
        try require(parcels.count <= 64, "Parcel mask capacity")
        var anchors: [Point] = []
        for a in d.anchors {
            try require(a.count == 2, "Invalid anchor")
            let x=a[0], y=a[1]
            try require(x > 0 && x < d.width-1 && y > 0 && y < d.height-2, "Anchor outside map")
            try require([UInt8(35),61,62,45,60].contains(tiles[(y-1)*d.width+x]), "Anchor has no floor")
            try require((0...2).allSatisfy { tiles[(y+$0)*d.width+x] == 46 || tiles[(y+$0)*d.width+x] == 80 }, "Blocked anchor")
            anchors.append(Point(x,y))
        }
        let hazards = try d.hazards.map { h -> Hazard in
            try require(h.period > 0 && h.on >= 0 && h.on <= h.period && h.x0 >= 0 && h.x1 < d.width && h.x0 <= h.x1 && h.y0 < h.y1 && h.phase >= 0, "Invalid hazard")
            return Hazard(x0:h.x0,x1:h.x1,y0:Int((h.y0*65536).rounded()),y1:Int((h.y1*65536).rounded()),period:h.period,on:h.on,phase:h.phase,kind:h.kind)
        }
        let forks = try d.forks.map { f -> Fork in
            try require(f.x0 >= 0 && f.x0 < f.x1 && f.x1 < d.finishX && !f.routes.isEmpty, "Invalid fork")
            let routes = try f.routes.map { r -> Route in
                let bands = try r.bands.map { b -> Band in
                    try require(b.count == 4, "Invalid route band")
                    try require(b[0] >= f.x0 && b[1] <= f.x1 && b[0] <= b[1] && b[2] <= b[3], "Band outside fork")
                    return Band(b[0],b[1],b[2],b[3])
                }
                return Route(name:r.name,bands:bands,entries:r.entry.map { e in Entry(x:Int((e.x*65536).rounded()), plan:e.plonkAt.map { .hopPlonk(e.hop,$0) } ?? .hop(e.hop)) },deltaCs:r.deltaCs,risk:r.risk,parcelDelta:r.parcelDelta)
            }
            return Fork(name:f.name,x0:f.x0,x1:f.x1,routes:routes)
        }
        return CourseData(name:d.name,w:d.width,h:d.height,finishX:d.finishX,startRow:d.startRow,tiles:tiles,hazards:hazards,forks:forks,parcels:parcels,anchors:anchors,chokepoints:d.chokepoints)
    }
    private struct Document: Decodable {
        var format: Int; var name: String; var width, height, finishX, startRow: Int
        var rows: [String]; var anchors: [[Int]]; var chokepoints: [Int]
        var hazards: [HazardDoc]; var forks: [ForkDoc]
    }
    private struct HazardDoc: Decodable { var kind: String; var x0,x1,period,on,phase: Int; var y0,y1: Double }
    private struct ForkDoc: Decodable { var name: String; var x0,x1: Int; var routes: [RouteDoc] }
    private struct RouteDoc: Decodable { var name: String; var bands: [[Int]]; var entry: [EntryDoc]; var deltaCs,risk,parcelDelta: Int }
    private struct EntryDoc: Decodable { var x: Double; var hop: Int; var plonkAt: Int? }
}
