import SwiftUI
import SpriteKit
import RoundersSim
import RoundersContent
import RoundersInput

@main struct RoundersApp: App {
    var body: some Scene { WindowGroup { RootView().statusBarHidden(true) } }
}
enum Screen { case title, race, pause, results }
@MainActor @Observable final class AppModel {
    var screen = Screen.title
    var regular=false
    var focus=0
    var lastDevice="Mouse / touch"
    var snapshot: RaceState?
    var countdown=""
    var debug=""
    var prompt=""
    var multiTouch=false
    var virtualOK=false
    var viewInsets=UIEdgeInsets.zero
    var active=true
    var firstRace=true
    @ObservationIgnored let course: CourseData
    @ObservationIgnored let controllers=ControllerHub()
    @ObservationIgnored var latch=InputLatch()
    @ObservationIgnored var touchBits: UInt8=0
    @ObservationIgnored var capturedTouch: UInt8=0
    @ObservationIgnored var zoneCounts=[0,0,0,0]
    @ObservationIgnored var seen: UInt8=0
    @ObservationIgnored var padSeen: UInt8=0
    @ObservationIgnored var raw: UInt8=0
    @ObservationIgnored var menuNeedsRelease=false
    @ObservationIgnored var menuPrevious: UInt8=0
    @ObservationIgnored var nextMove=0.0
    @ObservationIgnored lazy var scene=RaceScene(model:self)
    let args=ProcessInfo.processInfo.arguments
    var autoplay: Bool { args.contains("-autoplay") }
    var seed: UInt64 {
        if let i=args.firstIndex(of:"-seed"),i+1 < args.count { return UInt64(args[i+1]) ?? 42 }; return 42
    }
    init() {
        do { course=try CourseLoader.laundryLane() } catch { fatalError("Course resource failed validation: \(error)") }
        virtualOK=controllers.selfTest()
        controllers.onDisconnect={ [weak self] in if self?.screen == .race { self?.pause() } }
    }
    func transition(_ to: Screen) {
        screen=to; focus=0; latch.reset(suppressing:raw); capturedTouch=0; scene.resetClock(); menuPrevious=255; menuNeedsRelease=true
    }
    func start() { scene.start(seed:seed,regular:regular,autoplay:autoplay); transition(.race) }
    func pause() { if screen == .race { transition(.pause) } }
    func resume() { transition(.race) }
    func background(_ running: Bool) { active=running; if !running { pause() }; latch.reset(suppressing:raw); scene.resetClock() }
    func touch(_ bits: UInt8) {
        let edges=bits & ~touchBits
        for index in 0..<4 where edges & (1 << index) != 0 { zoneCounts[index] += 1 }
        capturedTouch |= edges; touchBits=bits
        if bits != 0 { lastDevice="Mouse / touch"; seen |= bits }
    }
    func confirm(_ index: Int? = nil) {
        if let index { focus=index }
        switch screen {
        case .title: if focus == 0 { start() } else { regular.toggle() }
        case .pause: if focus == 0 { resume() } else if focus == 1 { start() } else { transition(.title) }
        case .results: if focus == 0 { start() } else { transition(.title) }
        case .race: pause()
        }
    }
    func poll(_ now: Double) {
        let p=controllers.poll(), k=keyboard()
        raw=touchBits | p.bits | k.bits
        if p.bits != 0 || p.edges != 0 || p.menu != 0 || p.menuEdges != 0 { lastDevice="Controller"; padSeen |= p.bits | p.edges }
        else if k.bits != 0 || k.menu != 0 { lastDevice="Keyboard" }
        seen |= raw | p.edges | capturedTouch
        latch.sample(raw,capturedEdges:p.edges | capturedTouch); capturedTouch=0
        let menu=p.menu | k.menu
        var edges=(menu & ~menuPrevious) | p.menuEdges
        if menuNeedsRelease {
            edges=0
            if menu == 0 && p.menuEdges == 0 { menuNeedsRelease=false }
        }
        if active && !menuNeedsRelease {
            if screen == .race { if edges & 16 != 0 { pause() } }
            else {
                let count=screen == .pause ? 3 : 2
                if menu & 3 != 0 && (edges & 3 != 0 || now >= nextMove) {
                    focus=(focus+(menu & 1 != 0 ? count-1 : 1))%count; nextMove=now+0.18
                }
                if edges & 4 != 0 { confirm() }
                else if edges & (8|16) != 0 { if screen == .pause { resume() } else if screen == .results { transition(.title) } }
            }
        }
        menuPrevious=menu
        if args.contains("-inputDebug") || args.contains("-uiTest") {
            debug="input:\(InputFrame(bits:raw).names) seen:\(InputFrame(bits:seen).names) padSeen:\(padSeen) menu:\(menu) pads:\(controllers.count) mt:\(multiTouch) virtual:\(virtualOK ? "ok" : "no") tick:\(snapshot?.tick ?? 0) nodes:\(scene.nodeCount) zoneCounts:\(zoneCounts.map(String.init).joined(separator:","))"
        }
    }
}
struct RootView: View {
    @State private var model=AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpriteView(scene:model.scene,preferredFramesPerSecond:60).ignoresSafeArea()
                if model.screen == .race { RaceHUD(model:model,size:geo.size,insets:geo.safeAreaInsets) }
                if model.screen != .race { menu }
                if !model.debug.isEmpty {
                    Text(verbatim:model.debug).font(.system(size:9,design:.monospaced)).foregroundStyle(.white).padding(4).background(.black.opacity(0.7)).position(x:geo.size.width/2,y:geo.size.height-12).accessibilityIdentifier("debug.input").allowsHitTesting(false)
                }
            }
            .onAppear { if model.autoplay || model.args.contains("-uiTest") { model.start() } }
        }
        .ignoresSafeArea()
        .onChange(of:phase) { _,new in model.background(new == .active) }
    }
    private var menu: some View {
        ZStack {
            Color(red:0.96,green:0.93,blue:0.85).opacity(model.screen == .pause ? 0.94 : 0.98).ignoresSafeArea()
            HStack(spacing:48) {
                VStack(alignment:.leading,spacing:12) {
                    Text("ROUNDERS").font(.system(size:48,weight:.black,design:.rounded)).tracking(-2)
                    Text("COURIER DASH  /  DEMO 01").font(.system(size:11,weight:.bold,design:.monospaced)).tracking(2)
                    Rectangle().frame(width:72,height:5).foregroundStyle(.orange)
                    Text(model.screen == .title ? "Six oddballs. One delivery.\nMake the last hop count." : model.screen == .pause ? "THE ROUND IS ON HOLD" : "DELIVERY RECEIPT").font(.system(size:18,weight:.semibold,design:.rounded))
                    Text("LAUNDRY LANE • \(model.regular ? "REGULAR" : "ERRAND") FIELD\n5 AI rivals • 8 Starter Knacks").font(.system(size:11,design:.monospaced)).lineSpacing(6)
                    Text(model.lastDevice == "Controller" ? "D-pad to choose · Cross to confirm · Circle to go back" : "Click a choice · Hold right to Hop · Hold left to Tuck").font(.system(size:11)).foregroundStyle(.secondary).frame(maxWidth:300,alignment:.leading)
                }
                VStack(spacing:8) {
                    if model.screen == .title {
                        menuButton("LET’S ROUND",index:0,id:"menu.race")
                        menuButton("Difficulty: \(model.regular ? "Regular" : "Errand")",index:1,id:"menu.difficulty")
                        Text("Cross = Hop  /  Circle = Tuck or Plonk\nL1 / L2 & R1 / R2 = Knacks\nTriangle or Options = Pause").font(.system(size:11,design:.monospaced)).lineSpacing(5).padding(.top,12)
                    } else if model.screen == .pause {
                        menuButton("Resume",index:0,id:"menu.resume")
                        menuButton("Restart Round",index:1,id:"menu.restart")
                        menuButton("Quit to Title",index:2,id:"menu.title")
                    } else {
                        results
                        HStack {
                            menuButton("Race Again",index:0,id:"menu.again")
                            menuButton("Title",index:1,id:"menu.title")
                        }
                    }
                }.frame(width:model.screen == .results ? 350 : 260)
            }.foregroundStyle(Color(red:0.12,green:0.16,blue:0.27)).padding(30)
        }
    }
    private var results: some View {
        VStack(spacing:5) {
            Text("ROUND COMPLETE").font(.system(size:18,weight:.black,design:.rounded)).accessibilityIdentifier("results.title")
            if let s=model.snapshot {
                ForEach(Array(s.places.enumerated()),id:\.element) { place,id in
                    HStack {
                        Text("\(place+1). \(castNames[id])\(id == 0 ? " · YOU" : " · AI")").fontWeight(id == 0 ? .bold : .regular)
                        Spacer()
                        Text(verbatim:s.runners[id].finished >= 0 ? String(format:"%.2fs",Double(s.runners[id].finished)/60) : "DNF")
                        Text("\(s.runners[id].bonks) bonks").foregroundStyle(.secondary)
                    }.font(.system(size:11,design:.monospaced))
                }
            }
        }.padding(.bottom,6)
    }
    private func menuButton(_ title: String,index: Int,id: String) -> some View {
        Button { model.confirm(index) } label: {
            Text(verbatim:title).font(.system(size:15,weight:.bold,design:.rounded)).frame(maxWidth:.infinity).padding(.vertical,12)
                .foregroundStyle(model.focus == index ? .white : Color(red:0.12,green:0.16,blue:0.27))
                .background(model.focus == index ? Color(red:0.16,green:0.50,blue:0.56) : Color.white.opacity(0.6),in:RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).stroke(Color.black.opacity(0.15),lineWidth:1))
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
let castNames=["Clem","Bap","Tuppence","Humbug","Bobbin","Pumice"]
