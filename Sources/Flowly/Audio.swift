import Foundation
import AVFoundation
import CoreAudio

struct AudioDevice: Identifiable, Hashable { let id: AudioDeviceID; let uid: String; let name: String }

enum AudioDevices {
    static func inputs() -> [AudioDevice] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasInput(id), let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioDevice(id: id, uid: uid, name: name)
        }
    }
    static func hasInput(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16); defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buf) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(buf.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }
    static func string(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cf) == noErr, let s = cf?.takeRetainedValue() else { return nil }
        return s as String
    }
}

/// Captures mic audio and delivers 16 kHz mono Float32 samples (what Whisper wants).
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false
    var onLevel: ((Float) -> Void)?
    static let rate = 16000.0

    func start() throws {
        guard !isRecording else { return }
        let input = engine.inputNode
        if !Prefs.mic.isEmpty, var dev = AudioDevices.inputs().first(where: { $0.uid == Prefs.mic })?.id, let au = input.audioUnit {
            AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let inFmt = input.outputFormat(forBus: 0)
        guard inFmt.sampleRate > 0, let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.rate, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: inFmt, to: target) else { throw NSError(domain: "Flowly", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input available"]) }
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inFmt) { [weak self] buf, _ in
            guard let self else { return }
            let cap = AVAudioFrameCount(Double(buf.frameLength) * Self.rate / inFmt.sampleRate) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
            var fed = false
            var err: NSError?
            conv.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buf
            }
            guard err == nil, let ch = out.floatChannelData?[0] else { return }
            let n = Int(out.frameLength)
            let arr = Array(UnsafeBufferPointer(start: ch, count: n))
            self.lock.lock(); self.samples.append(contentsOf: arr); self.lock.unlock()
            var sum: Float = 0; for v in arr { sum += v * v }
            let rms = n > 0 ? (sum / Float(n)).squareRoot() : 0
            self.onLevel?(min(1, rms * 9))
        }
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    /// Thread-safe copy of the most recent audio (for live preview) and the total sample count.
    func snapshot(lastSeconds: Double) -> (samples: [Float], total: Int) {
        lock.lock(); defer { lock.unlock() }
        let n = Int(lastSeconds * Self.rate)
        return (Array(samples.suffix(n)), samples.count)
    }

    static func rms(_ s: [Float]) -> Float {
        guard !s.isEmpty else { return 0 }
        var sum: Float = 0; for v in s { sum += v * v }
        return (sum / Float(s.count)).squareRoot()
    }
}
