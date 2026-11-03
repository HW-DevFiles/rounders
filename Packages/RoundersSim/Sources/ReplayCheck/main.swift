import RoundersSim
import RoundersContent
let c = try CourseLoader.laundryLane()
var s = makeRace(.demo(seed:42,regular:true,autoplay:true),course:c)
while !s.complete { step(&s,inputs:[],course:c) }
print(String(stateHash(s),radix:16),s.tick,s.runners.map { $0.finished })
