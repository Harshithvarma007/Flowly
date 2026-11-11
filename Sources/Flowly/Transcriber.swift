import Foundation
import WhisperKit

/// Serializes access to the single Whisper model so live previews and the final pass never overlap.
actor Gate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async { if !busy { busy = true; return }; await withCheckedContinuation { waiters.append($0) } }
    func tryAcquire() -> Bool { if busy { return false }; busy = true; return true }
    func release() { if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() } }
}

@MainActor
final class Transcriber: ObservableObject {
    @Published var status = "Not loaded"
    @Published var progress: Double = 0
    @Published var ready = false
    @Published var loadedModel = ""
    private var kit: WhisperKit?
    private var loadingTask: Task<Void, Never>?
    var gate = Gate()

    static var modelsDir: URL {
        let u = Store.supportDir.appendingPathComponent("Models"); try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }

    func load(variant: String) {
        loadingTask?.cancel()
        ready = false; progress = 0; status = "Preparing \(variant)…"
        loadingTask = Task {
            do {
                status = "Downloading model…"
                let folder = try await WhisperKit.download(variant: variant, downloadBase: Self.modelsDir) { p in
                    Task { @MainActor in self.progress = p.fractionCompleted; self.status = "Downloading model… \(Int(p.fractionCompleted * 100))%" }
                }
                status = "Loading & optimizing for your Mac (first run takes a minute)…"; progress = 1
                let cfg = WhisperKitConfig(downloadBase: Self.modelsDir, modelFolder: folder.path, tokenizerFolder: Self.modelsDir, verbose: false, prewarm: true, load: true, download: false)
                let k = try await WhisperKit(cfg)
                if Task.isCancelled { return }
                kit = k; loadedModel = variant; ready = true; status = "Ready"
            } catch {
                status = "Model error: \(error.localizedDescription)"
            }
        }
    }

    /// If a transcription ever hangs, drop the stuck model state and reload it.
    func recover() { gate = Gate(); kit = nil; ready = false; load(variant: Prefs.model) }

    func transcribe(_ samples: [Float], language: String?, hints: [String]) async throws -> String {
        guard let kit else { throw NSError(domain: "Flowly", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model still loading"]) }
        var prompt: [Int]? = nil
        if !hints.isEmpty, let tok = kit.tokenizer {
            let ids = tok.encode(text: " " + hints.joined(separator: ", ")).filter { $0 < tok.specialTokens.specialTokenBegin }
            if !ids.isEmpty { prompt = Array(ids.prefix(100)) }
        }
        var opts = DecodingOptions(task: .transcribe, language: language, temperature: 0, usePrefillPrompt: true, detectLanguage: language == nil,
                                   skipSpecialTokens: true, withoutTimestamps: true, promptTokens: prompt, chunkingStrategy: .vad)
        if language == nil { opts.usePrefillPrompt = false }
        await gate.acquire()
        do {
            let results = try await kit.transcribe(audioArray: samples, decodeOptions: opts)
            await gate.release()
            return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { await gate.release(); throw error }
    }

    /// Fast, lower-fidelity pass over recent audio for the live preview. Skipped if the model is busy.
    func transcribePartial(_ samples: [Float], language: String?) async -> String? {
        guard let kit, await gate.tryAcquire() else { return nil }
        let opts = DecodingOptions(task: .transcribe, language: language, temperature: 0, usePrefillPrompt: language != nil, detectLanguage: language == nil,
                                   skipSpecialTokens: true, withoutTimestamps: true)
        let r = try? await kit.transcribe(audioArray: samples, decodeOptions: opts)
        await gate.release()
        return r.map { $0.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func transcribeFile(_ path: String) async throws -> String {
        guard let kit else { return "" }
        let r = try await kit.transcribe(audioPath: path)
        return r.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
