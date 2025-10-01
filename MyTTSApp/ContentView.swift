import SwiftUI
import AVFoundation
import Combine

class TtsManager: ObservableObject {
    @Published var status: String = "Ready"
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var tts: OpaquePointer?
    private var isInitialized = false
    private var audioFormat: AVAudioFormat?
    private var isPlayerConnected = false

    init() {
        setupAudioEngine()
        initializeTTS()
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let engine = audioEngine, let player = playerNode else { return }

        engine.attach(player)
        // Don't start engine yet - will start when first audio is played
    }

    private func initializeTTS() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async { self.status = "Loading model..." }

            let modelURL = Bundle.main.url(forResource: "model.fp16", withExtension: "onnx")
            let tokensURL = Bundle.main.url(forResource: "tokens", withExtension: "txt")
            let voicesURL = Bundle.main.url(forResource: "voices", withExtension: "bin")

            guard let resourcePath = Bundle.main.resourceURL else {
                DispatchQueue.main.async { self.status = "Failed to get resource path" }
                return
            }

            let espeakDataURL = resourcePath.appendingPathComponent("espeak-ng-data")

            var missingFiles: [String] = []
            if modelURL == nil { missingFiles.append("model.fp16.onnx") }
            if tokensURL == nil { missingFiles.append("tokens.txt") }
            if voicesURL == nil { missingFiles.append("voices.bin") }

            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: espeakDataURL.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                missingFiles.append("espeak-ng-data directory")
            }

            if !missingFiles.isEmpty {
                DispatchQueue.main.async {
                    self.status = "Missing: \(missingFiles.joined(separator: ", "))"
                }
                return
            }

            let modelPath = modelURL!.path
            let tokensPath = tokensURL!.path
            let voicesPath = voicesURL!.path
            let espeakDataPath = espeakDataURL.path

            espeakDataPath.withCString { cEspeakDataPath in
                modelPath.withCString { cModelPath in
                    tokensPath.withCString { cTokensPath in
                        voicesPath.withCString { cVoicesPath in

                            var kittenConfig = SherpaOnnxOfflineTtsKittenModelConfig(
                                model: cModelPath,
                                voices: cVoicesPath,
                                tokens: cTokensPath,
                                data_dir: cEspeakDataPath,
                                length_scale: 1.0
                            )

                            var modelConfig = SherpaOnnxOfflineTtsModelConfig(
                                vits: SherpaOnnxOfflineTtsVitsModelConfig(),
                                num_threads: 2, // Increased threads
                                debug: 0, // Disable debug for performance
                                provider: "cpu",
                                matcha: SherpaOnnxOfflineTtsMatchaModelConfig(),
                                kokoro: SherpaOnnxOfflineTtsKokoroModelConfig(),
                                kitten: kittenConfig,
                                zipvoice: SherpaOnnxOfflineTtsZipvoiceModelConfig()
                            )

                            var ttsConfig = SherpaOnnxOfflineTtsConfig(
                                model: modelConfig,
                                rule_fsts: nil,
                                max_num_sentences: 1,
                                rule_fars: nil,
                                silence_scale: 0.5 // Reduced silence
                            )

                            self.tts = SherpaOnnxCreateOfflineTts(&ttsConfig)

                            if self.tts != nil {
                                self.isInitialized = true
                                DispatchQueue.main.async {
                                    self.status = "Ready (optimized)"
                                }
                            } else {
                                DispatchQueue.main.async {
                                    self.status = "Failed to initialize TTS"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func synthesizeText(_ text: String) {
        guard isInitialized, let tts = tts else {
            status = "TTS not initialized"
            return
        }

        DispatchQueue.main.async {
            self.status = "Synthesizing..."
        }

        // Split text into sentences for streaming
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let startTime = Date()

            for (index, sentence) in sentences.enumerated() {
                if sentence.isEmpty { continue }

                let speakerId: Int32 = 0
                let speed: Float = 1.1 // Slightly faster for lower latency

                guard let generatedAudio = SherpaOnnxOfflineTtsGenerate(tts, sentence, speakerId, speed) else {
                    continue
                }

                let sampleCount = generatedAudio.pointee.n
                let sampleRate = generatedAudio.pointee.sample_rate

                if let samples = generatedAudio.pointee.samples {
                    // Play immediately without converting to file
                    self.playAudioStream(from: samples, count: Int(sampleCount), sampleRate: sampleRate)

                    if index == 0 {
                        let latency = Date().timeIntervalSince(startTime)
                        DispatchQueue.main.async {
                            self.status = "Playing (latency: \(String(format: "%.2f", latency))s)"
                        }
                    }
                }

                SherpaOnnxDestroyOfflineTtsGeneratedAudio(generatedAudio)
            }

            let totalTime = Date().timeIntervalSince(startTime)
            DispatchQueue.main.async {
                self.status = "Complete (\(String(format: "%.2f", totalTime))s total)"
            }
        }
    }

    private func playAudioStream(from samples: UnsafePointer<Float>, count: Int, sampleRate: Int32) {
        guard let player = playerNode, let engine = audioEngine else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!

        // Connect and start engine on first use
        if !isPlayerConnected {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            isPlayerConnected = true
            audioFormat = format

            do {
                try engine.start()
            } catch {
                print("❌ Failed to start audio engine: \(error)")
                return
            }
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(count)) else {
            return
        }

        buffer.frameLength = UInt32(count)

        // Copy samples to buffer
        if let channelData = buffer.floatChannelData {
            for i in 0..<count {
                channelData[0][i] = samples[i]
            }
        }

        // Schedule and play
        player.scheduleBuffer(buffer, completionHandler: nil)

        if !player.isPlaying {
            player.play()
        }
    }

    deinit {
        if let tts = tts {
            SherpaOnnxDestroyOfflineTts(tts)
        }
        audioEngine?.stop()
    }
}

struct ContentView: View {
    @StateObject private var ttsManager = TtsManager()
    @State private var inputText = """
KL Rahul is one of India’s most stylish batsmen.  
Born in Bengaluru, he developed his game at the KSCA.  
He made his Test debut in 2014 at the MCG.  
Rahul scored his first Test century at Sydney in 2015.  
He is known for his elegant stroke play.  
Rahul has represented India in all three formats.  
In the IPL, he has been a consistent run-scorer.  
He has led Punjab Kings as captain in the IPL.  
Rahul is admired for his calm temperament.  
He can open the innings or play in the middle order.  
Rahul’s wicketkeeping adds versatility to the team.  
He has scored centuries in Tests, ODIs, and T20Is.  
His cover drives are a delight to watch.  
Rahul has a reputation for timing the ball beautifully.  
He has rescued India on many tough occasions.  
Fitness and discipline are key parts of his routine.  
Rahul is also a reliable finisher in white-ball cricket.  
Fans value his adaptability across conditions.  
He remains one of India’s most dependable players.  
KL Rahul continues to inspire the next generation.
"""


    var body: some View {
        VStack(spacing: 20) {
            TextEditor(text: $inputText)
                .frame(height: 150)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )

            Button("Speak") {
                ttsManager.synthesizeText(inputText)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)

            Text(ttsManager.status)
                .padding()
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
