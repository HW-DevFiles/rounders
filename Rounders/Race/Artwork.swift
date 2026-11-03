import SpriteKit
import UIKit
import RoundersSim

@MainActor enum Ink {
    static let paper=UIColor(red:0.96,green:0.93,blue:0.85,alpha:1)
    static let peach=UIColor(red:0.95,green:0.63,blue:0.48,alpha:1)
    static let teal=UIColor(red:0.16,green:0.50,blue:0.56,alpha:1)
    static let navy=UIColor(red:0.12,green:0.16,blue:0.27,alpha:1)
    static let danger=UIColor(red:0.91,green:0.29,blue:0.18,alpha:1)
    static let parcel=UIColor(red:0.96,green:0.76,blue:0.05,alpha:1)
    static let categories=[UIColor.systemOrange,UIColor.systemPurple,teal,UIColor.systemGreen]
}
@MainActor enum Art {
    static func texture(_ size: CGSize=CGSize(width:64,height:64),_ draw: (CGContext)->Void) -> SKTexture {
        let image=UIGraphicsImageRenderer(size:size).image { context in draw(context.cgContext) }
        let t=SKTexture(image:image); t.filteringMode = .linear; return t
    }
    static let parcel=texture { c in
        c.setFillColor(Ink.parcel.cgColor); c.fill(CGRect(x:6,y:10,width:52,height:44))
        c.setStrokeColor(Ink.navy.cgColor); c.setLineWidth(3); c.stroke(CGRect(x:6,y:10,width:52,height:44))
        c.move(to:CGPoint(x:6,y:10)); c.addLine(to:CGPoint(x:32,y:32)); c.addLine(to:CGPoint(x:58,y:10)); c.strokePath()
    }
    static let danger=texture { c in
        c.setFillColor(Ink.danger.cgColor)
        for x in stride(from:0,to:64,by:16) { c.move(to:CGPoint(x:x,y:64)); c.addLine(to:CGPoint(x:x+8,y:6)); c.addLine(to:CGPoint(x:x+16,y:64)); c.closePath(); c.fillPath() }
    }
    static let pins=texture { c in c.setFillColor(UIColor.systemPurple.cgColor); for x in [10,32,54] { c.fillEllipse(in:CGRect(x:x-5,y:8,width:10,height:10)); c.fill(CGRect(x:x-1,y:16,width:2,height:42)) } }
    static let gum=texture { c in c.setFillColor(UIColor.systemPurple.withAlphaComponent(0.65).cgColor); c.fillEllipse(in:CGRect(x:0,y:12,width:64,height:40)) }
    static let dart=texture(CGSize(width:64,height:32)) { c in
        c.setFillColor(Ink.paper.cgColor); c.setStrokeColor(Ink.navy.cgColor); c.setLineWidth(2)
        c.move(to:CGPoint(x:2,y:2)); c.addLine(to:CGPoint(x:62,y:16)); c.addLine(to:CGPoint(x:2,y:30)); c.addLine(to:CGPoint(x:16,y:16)); c.closePath(); c.drawPath(using:.fillStroke)
    }
    static func runner(_ id: Int) -> SKTexture {
        texture { c in
            let colors=[UIColor.systemOrange,UIColor(red:0.76,green:0.55,blue:0.32,alpha:1),UIColor(red:0.67,green:0.60,blue:0.35,alpha:1),Ink.paper,Ink.teal,UIColor.systemGray]
            c.setFillColor(Ink.navy.withAlphaComponent(0.15).cgColor); c.fillEllipse(in:CGRect(x:8,y:7,width:52,height:52))
            c.setFillColor(colors[id].cgColor); c.fillEllipse(in:CGRect(x:5,y:5,width:52,height:52))
            c.setStrokeColor(Ink.navy.cgColor); c.setLineWidth(2.5); c.strokeEllipse(in:CGRect(x:5,y:5,width:52,height:52))
            c.saveGState(); c.addEllipse(in:CGRect(x:7,y:7,width:48,height:48)); c.clip()
            if id == 3 { c.setStrokeColor(Ink.danger.cgColor); c.setLineWidth(7); for x in stride(from:-60,to:100,by:20) { c.move(to:CGPoint(x:x,y:0)); c.addLine(to:CGPoint(x:x+64,y:64)); c.strokePath() } }
            if id == 1 { c.setStrokeColor(Ink.paper.cgColor); c.setLineWidth(3); for x in [14,24,34] { c.move(to:CGPoint(x:x,y:14)); c.addLine(to:CGPoint(x:x+8,y:20)); c.strokePath() } }
            if id == 2 || id == 4 { c.setStrokeColor(Ink.navy.withAlphaComponent(0.5).cgColor); c.strokeEllipse(in:CGRect(x:11,y:11,width:40,height:40)) }
            if id == 5 { c.setFillColor(Ink.paper.cgColor); for x in [12,25,40] { c.fillEllipse(in:CGRect(x:x,y:x/2,width:3,height:3)) } }
            c.restoreGState()
            if id == 0 { c.setFillColor(Ink.teal.cgColor); c.fillEllipse(in:CGRect(x:23,y:0,width:20,height:9)) }
            c.setFillColor(Ink.navy.cgColor); c.fillEllipse(in:CGRect(x:30,y:25,width:4,height:6)); c.fillEllipse(in:CGRect(x:44,y:25,width:4,height:6))
            c.setStrokeColor(Ink.navy.cgColor); c.setLineWidth(2); c.move(to:CGPoint(x:34,y:39)); c.addQuadCurve(to:CGPoint(x:46,y:37),control:CGPoint(x:41,y:43)); c.strokePath()
        }
    }
    static func tile(_ ch: UInt8) -> SKTexture {
        if ch == 94 || ch == 118 { return danger }
        return texture { c in
            let color: UIColor = ch == 62 ? Ink.teal : ch == 60 ? Ink.peach : ch == 72 ? Ink.peach : Ink.navy
            if ch == 83 {
                c.setFillColor(Ink.teal.cgColor); c.fill(CGRect(x:3,y:46,width:58,height:14))
                c.setStrokeColor(Ink.navy.cgColor); c.setLineWidth(4)
                c.move(to:CGPoint(x:10,y:46)); for i in 0..<5 { c.addLine(to:CGPoint(x:i%2 == 0 ? 48 : 16,y:46-i*8)) }; c.strokePath()
            } else {
                let height: CGFloat = ch == 61 || ch == 45 ? 7 : 64
                c.setFillColor(color.cgColor); c.fill(CGRect(x:0,y:0,width:64,height:height))
                c.setFillColor(Ink.teal.cgColor); c.fill(CGRect(x:0,y:0,width:64,height:3))
                if ch == 35 { c.setStrokeColor(Ink.paper.withAlphaComponent(0.16).cgColor); c.setLineWidth(1); c.stroke(CGRect(x:2,y:20,width:60,height:24)) }
                if ch == 62 || ch == 60 || ch == 72 {
                    c.setStrokeColor(Ink.paper.cgColor); c.setLineWidth(3)
                    for x in [12,36] { c.move(to:CGPoint(x:x,y:8)); c.addLine(to:CGPoint(x:x+9,y:15)); c.addLine(to:CGPoint(x:x,y:22)); c.strokePath() }
                }
                for y in stride(from:8,to:Int(height),by:12) { for x in stride(from:8,to:64,by:12) { c.setFillColor(Ink.paper.withAlphaComponent(0.10).cgColor); c.fillEllipse(in:CGRect(x:x,y:y,width:2,height:2)) } }
            }
        }
    }
}
@MainActor enum TerrainBuilder {
    static func build(_ c: CourseData,in root: SKNode) {
        var groups: [UInt8:SKTileGroup]=[:]
        for ch in Array("#=-><^vSH".utf8) { groups[ch]=SKTileGroup(tileDefinition:SKTileDefinition(texture:Art.tile(ch),size:CGSize(width:32,height:32))) }
        let set=SKTileSet(tileGroups:Array(groups.values),tileSetType:.grid)
        let map=SKTileMapNode(tileSet:set,columns:c.w,rows:c.h,tileSize:CGSize(width:32,height:32))
        map.anchorPoint = .zero; map.zPosition=0
        for x in 0..<c.w { for y in 0..<c.h { if let group=groups[c.at(x,y)] { map.setTileGroup(group,forColumn:x,row:y) } } }
        root.addChild(map)
        for (x,title) in [(30,"HOP  →"),(64,"TUCK  →"),(98,"THE WASH  ↑  →  ↓"),(291,"PLONK  ↓"),(335,"THE STACKS  ↑  →")] {
            let n=SKLabelNode(fontNamed:"AvenirNext-Heavy"); n.text=title; n.fontSize=14; n.fontColor=Ink.teal; n.position=CGPoint(x:x*32,y:14*32); root.addChild(n)
        }
        let finish=SKSpriteNode(color:Ink.teal,size:CGSize(width:6,height:240)); finish.position=CGPoint(x:c.finishX*32,y:14*32); root.addChild(finish)
        let label=SKLabelNode(fontNamed:"AvenirNext-Heavy"); label.text="DELIVERED"; label.fontColor=Ink.navy; label.fontSize=20; label.position=CGPoint(x:c.finishX*32,y:18*32); root.addChild(label)
    }
}
@MainActor final class RunnerView: SKNode {
    private let body: SKSpriteNode
    private let nameLabel=SKLabelNode(fontNamed:"AvenirNext-Bold")
    private let guardRing: SKSpriteNode
    private var pips: [SKSpriteNode]=[]
    private let shadow=SKSpriteNode(color:Ink.navy.withAlphaComponent(0.15),size:CGSize(width:32,height:4))
    init(cast: Int) {
        body=SKSpriteNode(texture:Art.runner(cast),size:CGSize(width:42,height:46)); body.anchorPoint=CGPoint(x:0.5,y:0)
        guardRing=SKSpriteNode(texture:Art.texture { c in c.setStrokeColor(Ink.teal.cgColor); c.setLineWidth(4); c.strokeEllipse(in:CGRect(x:2,y:2,width:60,height:60)) },size:CGSize(width:56,height:60))
        super.init(); zPosition=cast == 0 ? 10 : 8
        addChild(shadow); addChild(body); guardRing.position.y=24; addChild(guardRing)
        nameLabel.text=cast == 0 ? "▼ YOU" : castNames[cast]; nameLabel.fontSize=10; nameLabel.fontColor=Ink.navy; nameLabel.position.y=62; addChild(nameLabel)
        for i in 0..<2 { let p=SKSpriteNode(color:Ink.paper,size:CGSize(width:6,height:6)); p.position=CGPoint(x:i*9-4,y:54); addChild(p); pips.append(p) }
    }
    required init?(coder: NSCoder) { fatalError("Use init(cast:)") }
    func sync(_ r: Runner,position: CGPoint,hands: [Int],tier: Int?) {
        self.position=position; alpha = !r.alive ? 0.25 : r.invuln > 0 && (r.invuln/5)%2 == 0 ? 0.5 : 1
        body.yScale=r.tucked ? 0.5 : 1; body.xScale=r.tucked ? 1.10 : 1
        guardRing.isHidden=r.guardT == 0 && r.immuneT == 0
        body.color=r.statusT > 0 ? .systemPurple : .white; body.colorBlendFactor=r.statusT > 0 ? 0.3 : 0
        nameLabel.fontColor=tier == nil ? Ink.teal : Ink.navy
        for h in 0..<2 { pips[h].color=hands[h] >= 0 ? Ink.categories[hands[h] >> 1] : Ink.paper; pips[h].alpha=hands[h] >= 0 ? 1 : 0.3 }
    }
    func hop() { body.run(.sequence([.scaleX(to:0.85,y:1.12,duration:0.08),.scale(to:1,duration:0.1)]),withKey:"squash") }
    func land(roll: Bool) { body.run(.sequence([.scaleX(to:roll ? 1.25 : 1.12,y:0.75,duration:0.05),.scale(to:1,duration:0.14)]),withKey:"squash") }
    func bonk() { body.run(.rotate(byAngle:.pi*2,duration:0.4)) }
}
