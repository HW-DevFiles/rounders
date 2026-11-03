import SwiftUI
import UIKit
import RoundersSim

struct RaceHUD: View {
    var model: AppModel
    var size: CGSize
    var insets: EdgeInsets
    private var geometry: TouchGeometry { TouchGeometry(size:size,safe:model.viewInsets) }
    var body: some View {
        ZStack {
            VStack {
                HStack(spacing:16) {
                    if let s=model.snapshot {
                        Text("\((s.places.firstIndex(of:0) ?? 0)+1) / 6").font(.system(size:22,weight:.black,design:.rounded)).accessibilityIdentifier("hud.rank")
                        progress(s).frame(maxWidth:.infinity)
                        Text(verbatim:String(format:"%02d:%02d",s.tick/3600,(s.tick/60)%60)).font(.system(size:18,weight:.bold,design:.monospaced))
                    }
                    Button { model.pause() } label: { Image(systemName:"pause.fill").font(.title3).padding(12).background(.white.opacity(0.6),in:Circle()) }.accessibilityIdentifier("race.pause")
                }
                .padding(.horizontal,max(28,insets.leading+12)).padding(.top,max(12,insets.top+8))
                Spacer()
            }
            VStack(spacing:4) {
                if !model.countdown.isEmpty { Text(verbatim:model.countdown).font(.system(size:88,weight:.black,design:.rounded)).foregroundStyle(Color(uiColor:Ink.teal)) }
                if !model.prompt.isEmpty { Text(verbatim:model.prompt).font(.system(size:13,weight:.bold,design:.rounded)).padding(8).background(Color(uiColor:Ink.paper).opacity(0.93),in:Capsule()) }
            }.position(x:size.width/2,y:size.height*0.28).allowsHitTesting(false)
            hand(0,center:geometry.left)
            hand(1,center:geometry.right)
            Text(model.lastDevice == "Controller" ? "○  TUCK / PLONK" : "HOLD LEFT  ·  TUCK / PLONK").position(x:100,y:size.height-30).font(.system(size:9,weight:.bold,design:.monospaced)).allowsHitTesting(false)
            Text(model.lastDevice == "Controller" ? "×  HOP" : "HOLD RIGHT  ·  HOP").position(x:size.width-92,y:size.height-30).font(.system(size:9,weight:.bold,design:.monospaced)).allowsHitTesting(false)
        }.foregroundStyle(Color(uiColor:Ink.navy))
    }
    private func hand(_ h: Int,center: CGPoint) -> some View {
        let raw=model.snapshot?.inventories[0].hands[h] ?? -1
        let knack=Knack(rawValue:raw)
        let usable=model.snapshot.map { canUse($0,runner:0,hand:h,course:model.course) } ?? false
        return ZStack {
            Circle().fill(Color(uiColor:Ink.paper).opacity(0.90))
            Circle().strokeBorder(Color(uiColor:Ink.parcel),style:StrokeStyle(lineWidth:3,dash:[5,3]))
            VStack(spacing:3) {
                Text(model.lastDevice == "Controller" ? (h == 0 ? "L1 / L2" : "R1 / R2") : (h == 0 ? "LEFT HAND" : "RIGHT HAND")).font(.system(size:9,weight:.bold,design:.monospaced))
                Text(verbatim:knack?.icon ?? "—").font(.system(size:21,weight:.black,design:.rounded))
                Text(verbatim:knack?.name ?? "Find a Parcel").font(.system(size:9,weight:.semibold,design:.rounded)).multilineTextAlignment(.center)
            }.padding(8)
        }.frame(width:112,height:112).opacity(usable ? 1 : 0.55)
            .position(x:center.x,y:size.height-center.y).accessibilityElement(children:.combine).accessibilityIdentifier(h == 0 ? "hand.left" : "hand.right").allowsHitTesting(false)
    }
    private func progress(_ s: RaceState) -> some View {
        GeometryReader { g in
            ZStack(alignment:.leading) {
                Capsule().fill(Color(uiColor:Ink.navy).opacity(0.12)).frame(height:4)
                ForEach(0..<6,id:\.self) { i in
                    Circle().fill(i == 0 ? Color.orange : Color(uiColor:Ink.teal)).frame(width:i == 0 ? 12 : 7,height:i == 0 ? 12 : 7)
                        .overlay(Circle().stroke(Color(uiColor:Ink.paper),lineWidth:1))
                        .position(x:max(6,min(g.size.width-6,CGFloat(s.runners[i].x)/65536/CGFloat(model.course.finishX)*g.size.width)),y:g.size.height/2)
                }
            }.frame(height:g.size.height)
        }.frame(height:20).allowsHitTesting(false)
    }
}
