import SpriteKit
import UIKit
import RoundersSim
import RoundersInput

struct TouchGeometry {
    var size: CGSize
    var safe: UIEdgeInsets
    var left: CGPoint { CGPoint(x:max(200,safe.left+56),y:max(60,safe.bottom+56)) }
    var right: CGPoint { CGPoint(x:min(size.width-200,size.width-safe.right-56),y:left.y) }
    func zone(_ p: CGPoint) -> UInt8 {
        for (c,b) in [(left,UInt8(4)),(right,UInt8(8))] {
            if hypot(p.x-c.x,p.y-c.y) <= 56 { return b }
        }
        return p.x >= size.width/2 ? 1 : 2
    }
}
@MainActor final class RaceScene: SKScene {
    unowned let model: AppModel
    var state: RaceState?
    private var previous: RaceState?
    private var clock=TickClock()
    private var countdownLeft=180
    private var world=SKNode(), cam=SKCameraNode()
    private var runnerNodes: [RunnerView]=[]
    private var parcels: [SKSpriteNode]=[]
    private var hazards: [SKSpriteNode]=[]
    private var effects=SKNode()
    private var trapNodes: [SKSpriteNode]=[]
    private var dartNodes: [SKSpriteNode]=[]
    private var backdrops: [(SKNode,CGFloat)]=[]
    private var zones: [ObjectIdentifier: UInt8]=[:]
    private let sounds=SoundBank()
    private var lastSequence = -1
    private var frameCounter=0
    private var cameraReady=false
    init(model: AppModel) {
        self.model=model
        super.init(size:CGSize(width:874,height:402))
        scaleMode = .resizeFill; backgroundColor=Ink.paper
        addChild(world); addChild(cam); camera=cam
        TerrainBuilder.build(model.course,in:world)
        for i in 0..<6 { let n=RunnerView(cast:i); world.addChild(n); runnerNodes.append(n) }
        for p in model.course.parcels {
            let n=SKSpriteNode(texture:Art.parcel,size:CGSize(width:25,height:25)); n.position=CGPoint(x:(CGFloat(p.x)+0.5)*32,y:(CGFloat(p.y)+0.5)*32); n.zPosition=4; world.addChild(n); parcels.append(n)
        }
        for h in model.course.hazards {
            let n=SKSpriteNode(texture:Art.danger,size:CGSize(width:CGFloat(h.x1-h.x0+1)*32,height:CGFloat(h.y1-h.y0)/65536*32))
            n.position=CGPoint(x:CGFloat(h.x0+h.x1+1)*16,y:CGFloat(h.y0+h.y1)/65536*16); n.zPosition=5; world.addChild(n); hazards.append(n)
        }
        world.addChild(effects)
        for layer in 0..<3 {
            let root=SKNode(); root.zPosition=CGFloat(-10+layer); addChild(root)
            for j in 0..<13 {
                let n=SKSpriteNode(color:[Ink.peach.withAlphaComponent(0.15),Ink.teal.withAlphaComponent(0.12),Ink.navy.withAlphaComponent(0.08)][layer],size:CGSize(width:96+CGFloat((j*17)%60),height:100+CGFloat((j*41)%130)))
                n.anchorPoint=CGPoint(x:0,y:0); n.position=CGPoint(x:j*150,y:100+layer*20); root.addChild(n)
            }
            backdrops.append((root,CGFloat(layer+1)*0.12))
        }
        effects.zPosition=6
        for _ in 0..<54 { let node=SKSpriteNode(); node.isHidden=true; effects.addChild(node); trapNodes.append(node) }
        for _ in 0..<32 { let node=SKSpriteNode(texture:Art.dart,size:CGSize(width:25,height:12)); node.isHidden=true; effects.addChild(node); dartNodes.append(node) }
    }
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }
    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled=true; model.multiTouch=view.isMultipleTouchEnabled
        view.preferredFramesPerSecond=60
    }
    var nodeCount: Int {
        func count(_ node: SKNode) -> Int { 1+node.children.reduce(0) { $0+count($1) } }
        return count(self)
    }
    func resetClock() { clock.reset(); zones.removeAll(); model.touch(0) }
    func start(seed: UInt64,regular: Bool,autoplay: Bool) {
        state=makeRace(.demo(seed:seed,regular:regular,autoplay:autoplay),course:model.course)
        previous=state; countdownLeft=180; lastSequence = -1; cameraReady=false; sounds.prepare()
        model.snapshot=state; model.countdown="3"; clock.reset()
    }
    override func update(_ now: TimeInterval) {
        if let view, model.viewInsets != view.safeAreaInsets { model.viewInsets=view.safeAreaInsets }
        model.poll(now)
        let steps=clock.advance(now,running:model.active && model.screen == .race)
        guard var s=state else { return }
        for _ in 0..<steps {
            if countdownLeft > 0 {
                countdownLeft -= 1
                model.countdown=countdownLeft == 0 ? "" : String((countdownLeft+59)/60)
                model.latch.reset(suppressing:model.raw)
                continue
            }
            previous=s
            let local=model.latch.consume()
            RoundersSim.step(&s,inputs:[local],course:model.course)
            for e in s.events where e.sequence > lastSequence {
                lastSequence=e.sequence
                if e.runner == 0 { sounds.play(e.kind) }
                if e.kind == 0 { runnerNodes[e.runner].hop() }
                if e.kind == 1 { runnerNodes[e.runner].land(roll:e.payload == 1) }
                if e.kind == 6 { runnerNodes[e.runner].bonk() }
            }
            if s.complete { break }
        }
        state=s; frameCounter += 1
        if frameCounter%6 == 0 || s.complete { model.snapshot=s }
        if s.complete && model.screen == .race {
            model.snapshot=s
            if model.autoplay {
                let line="ROUNDERS_RESULT seed=\(s.config.seed) tick=\(s.tick) hash=\(String(stateHash(s),radix:16)) finishers=\(s.runners.filter { $0.finished >= 0 }.count) \(s.places.map { "\(castNames[$0]):\(s.runners[$0].finished)" })"
                NSLog("%@",line)
                // A simulator-console bridge may detach; retain the latest
                // diagnostic result inside this app's temporary directory too.
                let log=FileManager.default.temporaryDirectory.appendingPathComponent("rounders-autoplay.log")
                try? (line+"\n").write(to:log,atomically:true,encoding:.utf8)
            }
            model.firstRace=false; model.transition(.results)
        }
        render(s,alpha:clock.alpha)
    }
    private func render(_ s: RaceState,alpha: Double) {
        let c=model.course, r=s.runners[0], tile: CGFloat=32
        cam.setScale(11*tile/size.height)
        let widthTiles=size.width*cam.xScale/tile
        let targetX=(CGFloat(r.x)/65536+15-widthTiles/2)*tile
        let feet=CGFloat(r.y)/65536*tile
        let targetY=feet+1.65*tile
        if !cameraReady { cam.position=CGPoint(x:targetX,y:targetY); cameraReady=true }
        cam.position.x=targetX
        cam.position.y += (targetY-cam.position.y)*0.15
        // Smooth within the 30%...55% feet band, including low routes,
        // springs, fast Plonks and a respawn onto a different route.
        cam.position.y=min(feet+2.2*tile,max(feet-0.55*tile,cam.position.y))
        for (root,depth) in backdrops { root.position.x=cam.position.x*(1-depth)-600; root.position.y=cam.position.y*0.3-130 }
        for id in 0..<6 {
            let current=s.runners[id], old=previous?.runners[id] ?? current
            let blend=current.alive && old.alive && abs(current.x-old.x)<2*ONE
            let x=blend ? Double(old.x)+(Double(current.x-old.x)*alpha) : Double(current.x)
            let y=blend ? Double(old.y)+(Double(current.y-old.y)*alpha) : Double(current.y)
            runnerNodes[id].sync(current,position:CGPoint(x:x/65536*32,y:y/65536*32),hands:s.inventories[id].hands,tier:s.config.runners[id].botTier)
        }
        for i in parcels.indices { parcels[i].isHidden=s.inventories[0].parcels & (UInt64(1)<<i) != 0 }
        for (i,h) in c.hazards.enumerated() { hazards[i].alpha=(s.tick+s.config.clockOffset+h.phase)%h.period < h.on ? 1 : 0.12 }
        for (index,node) in trapNodes.enumerated() {
            node.isHidden=index >= s.traps.count
            if index < s.traps.count {
                let t=s.traps[index]
                node.texture=t.kind == 2 ? Art.pins : Art.gum
                node.size=CGSize(width:CGFloat(t.x1-t.x0)/65536*32,height:t.kind == 2 ? 14 : 8)
                node.position=CGPoint(x:CGFloat(t.x0+t.x1)/65536*16,y:CGFloat(t.y)/65536*32+4)
            }
        }
        for (index,node) in dartNodes.enumerated() {
            node.isHidden=index >= s.projectiles.count
            if index < s.projectiles.count {
                let p=s.projectiles[index]; node.position=CGPoint(x:CGFloat(p.x)/65536*32,y:CGFloat(p.y)/65536*32)
            }
        }
        for (lane,id) in s.runners.indices.sorted(by:{ s.runners[$0].x < s.runners[$1].x }).enumerated() { runnerNodes[id].labelLane(lane%3) }
        let x=r.x >> 16
        if countdownLeft > 0 { model.prompt="Hold right to Hop · Hold left to Tuck" }
        else if !r.alive { model.prompt="BONK! Back at your last Anchor…" }
        else if r.roll > 0 { model.prompt="PLONK-ROLL!" }
        else if model.firstRace && (34...44).contains(x) { model.prompt=model.lastDevice == "Controller" ? "Hold Cross for a higher Hop" : "Hold the right side for a higher Hop" }
        else if model.firstRace && (65...73).contains(x) { model.prompt=model.lastDevice == "Controller" ? "Hold Circle to Tuck" : "Hold the left side to Tuck" }
        else if (96...114).contains(x) { model.prompt="THE WASH  ↑ fast wire · → slates · ↓ sheltered gutter" }
        else if (294...313).contains(x) { model.prompt="COAL CHUTE  ·  Hop, then Down in the air to Plonk" }
        else if (334...350).contains(x) { model.prompt="THE STACKS  ↑ quick & risky · → safe attic" }
        else { model.prompt="" }
    }
    private func publish() { model.touch(zones.values.reduce(UInt8(0),|)) }
    override func touchesBegan(_ touches: Set<UITouch>,with event: UIEvent?) {
        guard model.screen == .race,let view else { return }
        let geometry=TouchGeometry(size:view.bounds.size,safe:view.safeAreaInsets)
        for touch in touches { let p=touch.location(in:view); zones[ObjectIdentifier(touch)]=geometry.zone(CGPoint(x:p.x,y:view.bounds.height-p.y)) }
        publish()
    }
    override func touchesEnded(_ touches: Set<UITouch>,with event: UIEvent?) { for touch in touches { zones[ObjectIdentifier(touch)]=nil }; publish() }
    override func touchesCancelled(_ touches: Set<UITouch>,with event: UIEvent?) { touchesEnded(touches,with:event) }
}
