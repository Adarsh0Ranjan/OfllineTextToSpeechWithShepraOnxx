import SwiftUI
import AVFoundation
import Combine

enum Language: String, CaseIterable, Identifiable {
    case english = "English"
    case french = "French"

    var id: String { rawValue }
    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .french: return "🇫🇷"
        }
    }
}

class MultiLanguageTtsManager: ObservableObject {
    @Published var status: String = "Ready"
    @Published var currentLanguage: Language = .english
    @Published var availableVoices: [Int32] = []

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var ttsInstances: [Language: OpaquePointer] = [:]
    private var voiceCounts: [Language: Int32] = [:]
    private var isPlayerConnected = false

    init() {
        setupAudioEngine()
        loadAllLanguages()
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        guard let engine = audioEngine, let player = playerNode else { return }
        engine.attach(player)
    }

    private func loadAllLanguages() {
        for language in Language.allCases {
            if initializeTTS(for: language) {
                print("✅ \(language.rawValue) loaded")
            }
        }

        // Set English as default
        if let voices = voiceCounts[.english] {
            availableVoices = Array(0..<voices)
            status = "Ready - English (\(voices) voices)"
        }
    }

    private func initializeTTS(for language: Language) -> Bool {
        guard let resourcePath = Bundle.main.resourceURL else { return false }
        let espeakDataPath = resourcePath.appendingPathComponent("espeak-ng-data").path

        var tts: OpaquePointer?

        switch language {
        case .english:
            // Kokoro model
            guard let modelURL = Bundle.main.url(forResource: "model_english", withExtension: "onnx"),
                  let tokensURL = Bundle.main.url(forResource: "tokens_english", withExtension: "txt"),
                  let voicesURL = Bundle.main.url(forResource: "voices_english", withExtension: "bin") else {
                print("❌ English: Files not found")
                return false
            }

            let modelPath = modelURL.path
            let tokensPath = tokensURL.path
            let voicesPath = voicesURL.path

            espeakDataPath.withCString { cEspeakDataPath in
                modelPath.withCString { cModelPath in
                    tokensPath.withCString { cTokensPath in
                        voicesPath.withCString { cVoicesPath in
                            var kokoroConfig = SherpaOnnxOfflineTtsKokoroModelConfig(
                                model: cModelPath,
                                voices: cVoicesPath,
                                tokens: cTokensPath,
                                data_dir: cEspeakDataPath,
                                length_scale: 1.0, dict_dir: nil,
                                lexicon: nil, lang: nil
                            )

                            var modelConfig = SherpaOnnxOfflineTtsModelConfig(
                                vits: SherpaOnnxOfflineTtsVitsModelConfig(),
                                num_threads: 2,
                                debug: 0,
                                provider: "cpu",
                                matcha: SherpaOnnxOfflineTtsMatchaModelConfig(),
                                kokoro: kokoroConfig,
                                kitten: SherpaOnnxOfflineTtsKittenModelConfig(),
                                zipvoice: SherpaOnnxOfflineTtsZipvoiceModelConfig()
                            )

                            var ttsConfig = SherpaOnnxOfflineTtsConfig(
                                model: modelConfig,
                                rule_fsts: nil,
                                max_num_sentences: 1,
                                rule_fars: nil,
                                silence_scale: 0.5
                            )

                            tts = SherpaOnnxCreateOfflineTts(&ttsConfig)
                        }
                    }
                }
            }

        case .french:
            // VITS Piper model
            guard let modelURL = Bundle.main.url(forResource: "model_french", withExtension: "onnx"),
                  let tokensURL = Bundle.main.url(forResource: "tokens_french", withExtension: "txt") else {
                print("❌ French: Files not found")
                return false
            }

            let modelPath = modelURL.path
            let tokensPath = tokensURL.path

            espeakDataPath.withCString { cEspeakDataPath in
                modelPath.withCString { cModelPath in
                    tokensPath.withCString { cTokensPath in
                        var vitsConfig = SherpaOnnxOfflineTtsVitsModelConfig(
                            model: cModelPath,
                            lexicon: "",
                            tokens: cTokensPath,
                            data_dir: cEspeakDataPath,
                            noise_scale: 0.667,
                            noise_scale_w: 0.8,
                            length_scale: 1.0,
                            dict_dir: ""
                        )

                        var modelConfig = SherpaOnnxOfflineTtsModelConfig(
                            vits: vitsConfig,
                            num_threads: 2,
                            debug: 0,
                            provider: "cpu",
                            matcha: SherpaOnnxOfflineTtsMatchaModelConfig(),
                            kokoro: SherpaOnnxOfflineTtsKokoroModelConfig(),
                            kitten: SherpaOnnxOfflineTtsKittenModelConfig(),
                            zipvoice: SherpaOnnxOfflineTtsZipvoiceModelConfig()
                        )

                        var ttsConfig = SherpaOnnxOfflineTtsConfig(
                            model: modelConfig,
                            rule_fsts: nil,
                            max_num_sentences: 1,
                            rule_fars: nil,
                            silence_scale: 0.5
                        )

                        tts = SherpaOnnxCreateOfflineTts(&ttsConfig)
                    }
                }
            }
        }

        if let tts = tts {
            let numSpeakers = SherpaOnnxOfflineTtsNumSpeakers(tts)
            ttsInstances[language] = tts
            voiceCounts[language] = numSpeakers
            return true
        }

        return false
    }

    func switchLanguage(_ language: Language) {
        currentLanguage = language
        if let voices = voiceCounts[language] {
            availableVoices = Array(0..<voices)
            status = "Ready - \(language.flag) \(language.rawValue) (\(voices) voices)"
        } else {
            availableVoices = []
            status = "\(language.rawValue) not available"
        }
    }

    func synthesizeText(_ text: String, voiceId: Int32 = 0, speed: Float = 1.0) {
        guard let tts = ttsInstances[currentLanguage] else {
            status = "\(currentLanguage.rawValue) not loaded"
            return
        }

        DispatchQueue.main.async {
            self.status = "Speaking \(self.currentLanguage.flag)..."
        }

        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            for sentence in sentences {
                if sentence.isEmpty { continue }

                guard let generatedAudio = SherpaOnnxOfflineTtsGenerate(tts, sentence, voiceId, speed) else {
                    continue
                }

                let sampleCount = generatedAudio.pointee.n
                let sampleRate = generatedAudio.pointee.sample_rate

                if let samples = generatedAudio.pointee.samples {
                    self.playAudioStream(from: samples, count: Int(sampleCount), sampleRate: sampleRate)
                }

                SherpaOnnxDestroyOfflineTtsGeneratedAudio(generatedAudio)
            }

            DispatchQueue.main.async {
                self.status = "Ready - \(self.currentLanguage.flag) \(self.currentLanguage.rawValue)"
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
        for (_, tts) in ttsInstances {
            SherpaOnnxDestroyOfflineTts(tts)
        }
        audioEngine?.stop()
    }
}

struct ContentView: View {
    @StateObject private var ttsManager = MultiLanguageTtsManager()
    @State private var selectedVoice: Int32 = 0
    @State private var speechSpeed: Float = 1.0
    @State private var inputText = "Hello! This is a test."

    var body: some View {
        VStack(spacing: 20) {
            Text("Multi-Language TTS")
                .font(.title)
                .bold()

            // Language selector
            Picker("Language", selection: $ttsManager.currentLanguage) {
                ForEach(Language.allCases) { lang in
                    Text("\(lang.flag) \(lang.rawValue)").tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: ttsManager.currentLanguage) { newLang in
                ttsManager.switchLanguage(newLang)
                selectedVoice = 0
            }

            // Voice selector
            if !ttsManager.availableVoices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Voice: \(selectedVoice)")
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

            Text(ttsManager.status)
                .padding()
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }
}
