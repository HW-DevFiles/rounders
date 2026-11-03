import AVFoundation

@MainActor final class SoundBank {
    private let engine=AVAudioEngine()
    private var players: [AVAudioPlayerNode]=[]
    private var buffers: [AVAudioPCMBuffer]=[]
    private var ready=false
    func prepare() {
        if ready { return }
        do { try AVAudioSession.sharedInstance().setCategory(.ambient,mode:.default) } catch { return }
        guard let format=AVAudioFormat(standardFormatWithSampleRate:44100,channels:1) else { return }
        for index in 0..<8 {
            let length=Int(44100*(index == 7 ? 0.45 : 0.10))
            guard let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(length)),let samples=buffer.floatChannelData?[0] else { return }
            buffer.frameLength=buffer.frameCapacity
            var noise: UInt32=UInt32(index+1)
            for i in 0..<length {
                let t=Double(i)/44100, fade=pow(1-Double(i)/Double(length),2)
                let frequency=[650.0,130,90,180,1000,430,75,880][index]
                noise=noise &* 1664525 &+ 1013904223
                let hiss=(Double(noise & 65535)/32768-1)*0.2
                let tone=sin(2*Double.pi*frequency*t*(index == 0 ? 1+t*3 : 1))
                samples[i]=Float((tone*0.65+hiss)*fade*0.16)
            }
            let player=AVAudioPlayerNode(); engine.attach(player); engine.connect(player,to:engine.mainMixerNode,format:format)
            players.append(player); buffers.append(buffer)
        }
        do { try engine.start(); ready=true } catch { return }
    }
    func play(_ kind: Int) {
        guard ready,kind < 8 else { return }
        let p=players[kind]
        p.stop(); p.scheduleBuffer(buffers[kind]); p.play()
    }
}
