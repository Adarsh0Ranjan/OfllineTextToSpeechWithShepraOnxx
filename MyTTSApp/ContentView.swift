import SwiftUI
import AVFoundation
import Combine

class TtsManager: ObservableObject {
    @Published var status: String = "Ready"
    @Published var availableVoices: [Int32] = []

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var tts: OpaquePointer?
    private var isInitialized = false
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
                                num_threads: 2,
                                debug: 0,
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
                                silence_scale: 0.5
                            )

                            self.tts = SherpaOnnxCreateOfflineTts(&ttsConfig)

                            if self.tts != nil {
                                self.isInitialized = true

                                // Get number of available speakers
                                let numSpeakers = SherpaOnnxOfflineTtsNumSpeakers(self.tts)
                                print("Available speakers: \(numSpeakers)")

                                DispatchQueue.main.async {
                                    self.availableVoices = Array(0..<numSpeakers)
                                    self.status = "Ready - \(numSpeakers) voices available"
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

    func synthesizeText(_ text: String, voiceId: Int32 = 0, speed: Float = 1.0) {
        guard isInitialized, let tts = tts else {
            status = "TTS not initialized"
            return
        }

        DispatchQueue.main.async {
            self.status = "Synthesizing with voice \(voiceId)..."
        }

        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let startTime = Date()

            for (index, sentence) in sentences.enumerated() {
                if sentence.isEmpty { continue }

                guard let generatedAudio = SherpaOnnxOfflineTtsGenerate(tts, sentence, voiceId, speed) else {
                    continue
                }

                let sampleCount = generatedAudio.pointee.n
                let sampleRate = generatedAudio.pointee.sample_rate

                if let samples = generatedAudio.pointee.samples {
                    self.playAudioStream(from: samples, count: Int(sampleCount), sampleRate: sampleRate)

                    if index == 0 {
                        let latency = Date().timeIntervalSince(startTime)
                        DispatchQueue.main.async {
                            self.status = "Voice \(voiceId) (latency: \(String(format: "%.2f", latency))s)"
                        }
                    }
                }

                SherpaOnnxDestroyOfflineTtsGeneratedAudio(generatedAudio)
            }

            DispatchQueue.main.async {
                self.status = "Ready - \(self.availableVoices.count) voices available"
            }
        }
    }

    private func playAudioStream(from samples: UnsafePointer<Float>, count: Int, sampleRate: Int32) {
        guard let player = playerNode, let engine = audioEngine else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!

        if !isPlayerConnected {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            isPlayerConnected = true

            do {
                try engine.start()
            } catch {
                print("Failed to start audio engine: \(error)")
                return
            }
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(count)) else {
            return
        }

        buffer.frameLength = UInt32(count)

        if let channelData = buffer.floatChannelData {
            for i in 0..<count {
                channelData[0][i] = samples[i]
            }
        }

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
    @State private var selectedVoice: Int32 = 0
    @State private var speechSpeed: Float = 1.0
    @State private var inputText = "Hello! This is a test of text to speech. I am testing different voices."

    var body: some View {
        VStack(spacing: 20) {
            Text("TTS Voice Tester")
                .font(.title)
                .bold()

            // Voice selector
            if !ttsManager.availableVoices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Voice Selection")
                        .font(.headline)

                    Picker("Voice", selection: $selectedVoice) {
                        ForEach(ttsManager.availableVoices, id: \.self) { voiceId in
                            Text("Voice \(voiceId)").tag(voiceId)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
            }

            // Speed control
            VStack(alignment: .leading, spacing: 8) {
                Text("Speed: \(String(format: "%.1f", speechSpeed))x")
                    .font(.headline)

                Slider(value: $speechSpeed, in: 0.5...2.0, step: 0.1)
            }
            .padding(.horizontal)

            // Text input
            TextEditor(text: $inputText)
                .frame(height: 100)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
                .padding(.horizontal)

            // Speak button
            Button("Speak") {
                ttsManager.synthesizeText(inputText, voiceId: selectedVoice, speed: speechSpeed)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal)

            // Quick test buttons
            HStack(spacing: 12) {
                ForEach(ttsManager.availableVoices.prefix(4), id: \.self) { voiceId in
                    Button("Test \(voiceId)") {
                        ttsManager.synthesizeText("This is voice number \(voiceId).", voiceId: voiceId, speed: speechSpeed)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
                }
            }

            Text(ttsManager.status)
                .padding()
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }
}
