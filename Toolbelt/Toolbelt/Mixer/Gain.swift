import CoreAudio

/// Real-time render: copies the tapped (input) Float32 audio to the output with gain and returns the
/// output peak. Allocation-free; handles interleaved or planar buffers on either side. Mono input is
/// spread to every output channel; extra output channels beyond the input's are silenced.
enum Gain {
    static func render(input: UnsafeMutableAudioBufferListPointer,
                       output: UnsafeMutableAudioBufferListPointer, gain: Float) -> Float {
        var inChannels = 0
        for b in input { inChannels += Int(b.mNumberChannels) }
        var peak: Float = 0
        var outChannel = 0
        for ob in output {
            let oc = max(Int(ob.mNumberChannels), 1)
            guard let od = ob.mData?.assumingMemoryBound(to: Float.self) else { outChannel += oc; continue }
            let outFrames = Int(ob.mDataByteSize) / (4 * oc)
            for c in 0..<oc {
                defer { outChannel += 1 }
                let source = inChannels == 1 ? 0 : outChannel
                var copied = 0
                if source < inChannels {
                    // Locate the input buffer and channel offset holding `source`.
                    var remaining = source
                    for ib in input {
                        let ic = Int(ib.mNumberChannels)
                        if remaining >= ic { remaining -= ic; continue }
                        if let id = ib.mData?.assumingMemoryBound(to: Float.self), ic > 0 {
                            let frames = min(outFrames, Int(ib.mDataByteSize) / (4 * ic))
                            for f in 0..<frames {
                                let s = id[f * ic + remaining] * gain
                                od[f * oc + c] = s
                                let a = abs(s)
                                if a > peak { peak = a }
                            }
                            copied = frames
                        }
                        break
                    }
                }
                for f in copied..<outFrames { od[f * oc + c] = 0 }
            }
        }
        return peak
    }
}
