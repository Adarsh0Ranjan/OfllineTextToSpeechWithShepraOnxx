import SwiftUI
import AVFoundation
import Combine
import ZIPFoundation
import SWCompression

// MARK: - Language Configuration
enum Language: String, CaseIterable {
    case english = "English"
    case french = "French"
    case chinese = "Chinese"
    case arabic = "Arabic"
    case spanish = "Spanish"

    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .french: return "🇫🇷"
        case .chinese: return "🇨🇳"
        case .arabic: return "🇸🇦"
        case .spanish: return "🇪🇸"
        }
    }

    var modelFiles: [String] {
        switch self {
        case .english:
            return ["model.onnx", "tokens.txt", "voices.bin", "lexicon.txt", "dict"]
        case .french:
            return ["fr_FR-siwis-medium.onnx", "fr_FR-siwis-medium.onnx.json"]
        case .chinese:
            return ["model.onnx", "tokens.txt", "lexicon.txt", "dict"]
        case .arabic:
            return ["ar_SA-miro-high.onnx", "ar_SA-miro-high.onnx.json"]
        case .spanish:
            return ["es_ES-davefx-medium.onnx", "es_ES-davefx-medium.onnx.json"]
        }
    }

    var baseURL: String {
        // Replace with your actual CDN/server URL
        return "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models"
    }

    var archiveFileName: String {
        switch self {
        case .english:
            return "kokoro-en-v0_19.tar.bz2"
        case .french:
            return "vits-piper-fr_FR-siwis-medium.tar.bz2"
        case .chinese:
            return "vits-melo-tts-zh_en.tar.bz2"
        case .arabic:
            return "vits-piper-ar_JO-SA_miro-high.tar.bz2"
        case .spanish:
            return "vits-piper-es_ES-davefx-medium.tar.bz2"
        }
    }

    var estimatedSize: String {
        switch self {
        case .english: return "~150 MB"
        case .french: return "~120 MB"
        case .chinese: return "~180 MB"
        case .arabic: return "~130 MB"
        case .spanish: return "~125 MB"
        }
    }
}

// MARK: - Model Manager with Detailed Logging
import Foundation
import Combine
import ZIPFoundation

class ModelDownloadManager: ObservableObject {
    @Published var downloadProgress: [Language: Double] = [:]
    @Published var downloadStatus: [Language: DownloadStatus] = [:]
    @Published var isDownloading = false

    enum DownloadStatus: Equatable {
        case notDownloaded
        case downloading
        case downloaded
        case failed(String)
    }

    private let fileManager = FileManager.default
    private var downloadTasks: [Language: URLSessionDownloadTask] = [:]

    var modelsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("TTSModels")
    }

    init() {
        log("🔧 Initializing ModelDownloadManager")
        createModelsDirectoryIfNeeded()
        checkDownloadedModels()
    }

    private func log(_ message: String) {
        print("🪵 [ModelDownloadManager] \(message)")
    }

    private func createModelsDirectoryIfNeeded() {
        do {
            try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            log("✅ Created models directory at \(modelsDirectory.path)")
        } catch {
            log("❌ Failed to create models directory: \(error.localizedDescription)")
        }
    }

    func checkDownloadedModels() {
        log("🔍 Checking which models are already downloaded...")
        for language in Language.allCases {
            if isModelDownloaded(language) {
                downloadStatus[language] = .downloaded
                log("✅ \(language.rawValue) model found.")
            } else {
                downloadStatus[language] = .notDownloaded
                log("ℹ️ \(language.rawValue) model not found.")
            }
        }
    }

    func isModelDownloaded(_ language: Language) -> Bool {
        let languageDir = modelsDirectory.appendingPathComponent(language.rawValue.lowercased())
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: languageDir.path, isDirectory: &isDirectory) && isDirectory.boolValue
        log("🧭 Checking \(language.rawValue): exists=\(exists), path=\(languageDir.path)")
        return exists
    }

    func downloadModel(for language: Language, completion: @escaping (Bool, String?) -> Void) {
        guard downloadStatus[language] != .downloading else {
            log("⚠️ Download for \(language.rawValue) already in progress.")
            return
        }

        DispatchQueue.main.async {
            self.downloadStatus[language] = .downloading
            self.downloadProgress[language] = 0.0
            self.isDownloading = true
        }

        let archiveName = language.archiveFileName
        let downloadURL = URL(string: "\(language.baseURL)/\(archiveName)")!
        log("⬇️ Starting download for \(language.rawValue) from \(downloadURL.absoluteString)")

        let task = URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            if let error = error {
                self.log("❌ Download error for \(language.rawValue): \(error.localizedDescription)")
                self.handleDownloadCompletion(for: language, success: false, error: error.localizedDescription, completion: completion)
                return
            }

            guard let tempURL = tempURL else {
                self.log("❌ tempURL is nil for \(language.rawValue)")
                self.handleDownloadCompletion(for: language, success: false, error: "Temporary file URL is nil.", completion: completion)
                return
            }

            self.log("📦 Download complete for \(language.rawValue). Temp file: \(tempURL.path)")

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let languageDir = self.modelsDirectory.appendingPathComponent(language.rawValue.lowercased())

                    // Cleanup existing directory
                    if self.fileManager.fileExists(atPath: languageDir.path) {
                        self.log("🧹 Removing old directory for \(language.rawValue)")
                        try self.fileManager.removeItem(at: languageDir)
                    }

                    try self.fileManager.createDirectory(at: languageDir, withIntermediateDirectories: true)
                    self.log("📁 Created new directory for \(language.rawValue): \(languageDir.path)")

                    // Step 1: Load compressed data
                    let compressedData = try Data(contentsOf: tempURL)
                    self.log("💾 Read \(compressedData.count) bytes of compressed data for \(language.rawValue)")

                    // Step 2: Decompress BZip2
                    let tarData = try BZip2.decompress(data: compressedData)
                    self.log("🫧 Successfully decompressed BZip2 archive for \(language.rawValue)")

                    // Step 3: Extract TAR entries
                    let entries = try TarContainer.open(container: tarData)
                    self.log("📦 TAR opened: \(entries.count) entries found for \(language.rawValue)")

                    var extractedCount = 0
                    for entry in entries {
                        let destinationURL = languageDir.appendingPathComponent(entry.info.name)
                        if entry.info.type == .directory {
                            try self.fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                        } else if let fileData = entry.data {
                            try fileData.write(to: destinationURL)
                        }
                        extractedCount += 1
                    }
                    self.log("✅ Extracted \(extractedCount) entries for \(language.rawValue)")

                    // Step 4: Flatten structure
                    try self.flattenDirectory(at: languageDir)
                    self.log("📂 Flattened directory for \(language.rawValue)")

                    self.handleDownloadCompletion(for: language, success: true, error: nil, completion: completion)
                } catch {
                    self.log("❌ Extraction failed for \(language.rawValue): \(error.localizedDescription)")
                    self.handleDownloadCompletion(for: language, success: false, error: error.localizedDescription, completion: completion)
                }
            }
        }

        downloadTasks[language] = task
        task.resume()
        log("🚀 Download task started for \(language.rawValue)")
    }

    private func handleDownloadCompletion(for language: Language, success: Bool, error: String?, completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.main.async {
            self.downloadStatus[language] = success ? .downloaded : .failed(error ?? "Unknown error")
            self.downloadProgress[language] = success ? 1.0 : 0.0
            self.isDownloading = self.downloadStatus.values.contains(.downloading)
            if success {
                self.log("✅ Completed successfully for \(language.rawValue)")
            } else {
                self.log("❌ Completed with error for \(language.rawValue): \(error ?? "Unknown")")
            }
            completion(success, error)
        }
    }

    private func flattenDirectory(at url: URL) throws {
        log("📁 Flattening directory at \(url.path)")
        let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        if contents.count == 1, let nestedDir = contents.first, nestedDir.hasDirectoryPath {
            let nestedContents = try fileManager.contentsOfDirectory(at: nestedDir, includingPropertiesForKeys: nil)
            for item in nestedContents {
                let destinationURL = url.appendingPathComponent(item.lastPathComponent)
                try fileManager.moveItem(at: item, to: destinationURL)
                log("📦 Moved \(item.lastPathComponent) to \(destinationURL.lastPathComponent)")
            }
            try fileManager.removeItem(at: nestedDir)
            log("🗑️ Removed nested directory \(nestedDir.lastPathComponent)")
        } else {
            log("ℹ️ No flattening needed for \(url.lastPathComponent)")
        }
    }

    func deleteModel(for language: Language) {
        let languageDir = modelsDirectory.appendingPathComponent(language.rawValue.lowercased())
        log("🗑️ Deleting model for \(language.rawValue) at \(languageDir.path)")
        do {
            try fileManager.removeItem(at: languageDir)
            log("✅ Deleted model for \(language.rawValue)")
        } catch {
            log("❌ Failed to delete model for \(language.rawValue): \(error.localizedDescription)")
        }

        DispatchQueue.main.async {
            self.downloadStatus[language] = .notDownloaded
            self.downloadProgress[language] = 0.0
        }
    }

    func getModelPath(for language: Language, file: String) -> String? {
        let languageDir = modelsDirectory.appendingPathComponent(language.rawValue.lowercased())
        let filePath = languageDir.appendingPathComponent(file)
        let exists = fileManager.fileExists(atPath: filePath.path)
        log("📄 getModelPath: \(file) for \(language.rawValue) — exists: \(exists)")
        return exists ? filePath.path : nil
    }
}


// MARK: - Updated TTS Manager
class MultiLanguageTtsManager: ObservableObject {
    @Published var status: String = "Ready"
    @Published var currentLanguage: Language = .english
    @Published var availableVoices: [Int32] = []

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var ttsInstances: [Language: OpaquePointer] = [:]
    private var voiceCounts: [Language: Int32] = [:]

    let modelManager = ModelDownloadManager()

    init() {
        log("🔧 Initializing MultiLanguageTtsManager")
        setupAudioEngine()

        if modelManager.isModelDownloaded(.english) {
            _ = initializeTTS(for: .english)
        }
    }

    private func log(_ message: String) {
        print("🪵 [MultiLanguageTtsManager] \(message)")
    }

    private func setupAudioEngine() {
        if let engine = audioEngine {
            engine.stop()
            if let player = playerNode {
                engine.detach(player)
            }
        }

        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let engine = audioEngine, let player = playerNode else {
            log("❌ Failed to setup audio engine/player")
            return
        }

        engine.attach(player)
        log("✅ Audio engine setup complete")
    }

    private func initializeTTS(for language: Language) -> Bool {
        if ttsInstances[language] != nil {
            log("ℹ️ TTS already initialized for \(language.rawValue)")
            return true
        }

        guard modelManager.isModelDownloaded(language) else {
            log("❌ Model not downloaded for \(language.rawValue)")
            return false
        }

        guard let resourcePath = Bundle.main.resourceURL else {
            log("❌ Failed to get Bundle resource URL")
            return false
        }

        let espeakDataPath = resourcePath.appendingPathComponent("espeak-ng-data").path
        var tts: OpaquePointer?

        log("🔍 Initializing TTS for \(language.rawValue)")

        func logAndCreateTTS(create: () -> OpaquePointer?) -> OpaquePointer? {
            let instance = create()
            if instance != nil {
                log("✅ TTS initialized for \(language.rawValue)")
            } else {
                log("❌ Failed to initialize TTS for \(language.rawValue)")
            }
            return instance
        }

        switch language {
        case .english:
            guard let modelPath = modelManager.getModelPath(for: language, file: "model.onnx"),
                  let tokensPath = modelManager.getModelPath(for: language, file: "tokens.txt"),
                  let voicesPath = modelManager.getModelPath(for: language, file: "voices.bin") else {
                log("❌ English model files missing")
                return false
            }

            tts = logAndCreateTTS {
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
                                    lexicon: nil,
                                    lang: nil
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

                                return SherpaOnnxCreateOfflineTts(&ttsConfig)
                            }
                        }
                    }
                }
            }

        case .french, .arabic, .spanish:
            guard let modelPath = modelManager.getModelPath(for: language, file: "model_\(language.rawValue.lowercased()).onnx"),
                  let tokensPath = modelManager.getModelPath(for: language, file: "tokens_\(language.rawValue.lowercased()).txt") else {
                log("❌ \(language.rawValue) model files missing")
                return false
            }

            tts = logAndCreateTTS {
                espeakDataPath.withCString { cEspeakDataPath in
                    modelPath.withCString { cModelPath in
                        tokensPath.withCString { cTokensPath in
                            var vitsConfig = SherpaOnnxOfflineTtsVitsModelConfig(
                                model: cModelPath,
                                lexicon: nil,
                                tokens: cTokensPath,
                                data_dir: cEspeakDataPath,
                                noise_scale: 0.667,
                                noise_scale_w: 0.8,
                                length_scale: 1.0,
                                dict_dir: nil
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

                            return SherpaOnnxCreateOfflineTts(&ttsConfig)
                        }
                    }
                }
            }

        case .chinese:
            guard let modelPath = modelManager.getModelPath(for: language, file: "model_chinese.onnx"),
                  let tokensPath = modelManager.getModelPath(for: language, file: "tokens_chinese.txt"),
                  let lexiconPath = modelManager.getModelPath(for: language, file: "lexicon_chinese.txt") else {
                log("❌ Chinese model files missing")
                return false
            }

            let dictDirPath = modelManager.modelsDirectory
                .appendingPathComponent("chinese")
                .appendingPathComponent("dict_chinese").path

            tts = logAndCreateTTS {
                modelPath.withCString { cModelPath in
                    tokensPath.withCString { cTokensPath in
                        lexiconPath.withCString { cLexiconPath in
                            dictDirPath.withCString { cDictDirPath in
                                var vitsConfig = SherpaOnnxOfflineTtsVitsModelConfig(
                                    model: cModelPath,
                                    lexicon: cLexiconPath,
                                    tokens: cTokensPath,
                                    data_dir: nil,
                                    noise_scale: 0.667,
                                    noise_scale_w: 0.8,
                                    length_scale: 1.0,
                                    dict_dir: cDictDirPath
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

                                return SherpaOnnxCreateOfflineTts(&ttsConfig)
                            }
                        }
                    }
                }
            }
        }

        if let tts = tts {
            let numSpeakers = SherpaOnnxOfflineTtsNumSpeakers(tts)
            ttsInstances[language] = tts
            voiceCounts[language] = numSpeakers
            log("✅ \(language.rawValue) loaded with \(numSpeakers) voices")
            return true
        }

        return false
    }

    func switchLanguage(_ language: Language, downloadIfNeeded: Bool = true) {
        log("🌐 Switching language to \(language.rawValue)")
        currentLanguage = language

        if modelManager.isModelDownloaded(language) {
            if ttsInstances[language] == nil {
                status = "Loading \(language.flag) \(language.rawValue)..."
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }
                    let success = self.initializeTTS(for: language)

                    DispatchQueue.main.async {
                        if success, let voices = self.voiceCounts[language] {
                            self.availableVoices = Array(0..<voices)
                            self.status = "Ready - \(language.flag) \(language.rawValue)"
                        } else {
                            self.status = "Failed to load \(language.rawValue)"
                        }
                    }
                }
            } else {
                if let voices = voiceCounts[language] {
                    availableVoices = Array(0..<voices)
                    status = "Ready - \(language.flag) \(language.rawValue)"
                }
            }
            setupAudioEngine()
        } else if downloadIfNeeded {
            status = "Model not downloaded"
            log("⚠️ Model for \(language.rawValue) not downloaded")
        }
    }

    func synthesizeText(_ text: String, voiceId: Int32 = 0, speed: Float = 1.0) {
        log("🗣️ Synthesizing text for \(currentLanguage.rawValue)")
        guard let tts = ttsInstances[currentLanguage] else {
            status = "\(currentLanguage.rawValue) not loaded"
            log("❌ TTS instance not found for \(currentLanguage.rawValue)")
            return
        }

        status = "Speaking \(currentLanguage.flag)..."

        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            for sentence in sentences {
                guard let generatedAudio = SherpaOnnxOfflineTtsGenerate(tts, sentence, voiceId, speed) else {
                    self.log("❌ Failed to generate audio for sentence: \(sentence)")
                    continue
                }

                let sampleCount = generatedAudio.pointee.n
                let sampleRate = generatedAudio.pointee.sample_rate

                if let samples = generatedAudio.pointee.samples {
                    self.playAudioStream(from: samples, count: Int(sampleCount), sampleRate: sampleRate)
                }

                SherpaOnnxDestroyOfflineTtsGeneratedAudio(generatedAudio)
                self.log("✅ Played sentence: \(sentence)")
            }

            DispatchQueue.main.async {
                self.status = "Ready - \(self.currentLanguage.flag) \(self.currentLanguage.rawValue)"
            }
        }
    }

    private func playAudioStream(from samples: UnsafePointer<Float>, count: Int, sampleRate: Int32) {
        guard let player = playerNode, let engine = audioEngine else {
            log("❌ Audio engine/player not initialized")
            return
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        if !engine.isRunning {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try? engine.start()
            log("🎛️ Audio engine started")
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(count)) else {
            log("❌ Failed to create PCM buffer")
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
        log("🛑 Destroying TTS instances and stopping audio engine")
        for (_, tts) in ttsInstances {
            SherpaOnnxDestroyOfflineTts(tts)
        }
        audioEngine?.stop()
    }
}


// MARK: - SwiftUI Views
struct ContentView: View {
    @StateObject private var ttsManager = MultiLanguageTtsManager()
    @StateObject private var modelManager: ModelDownloadManager
    @State private var selectedVoice: Int32 = 0
    @State private var speechSpeed: Float = 1.0
    @State private var inputText = "Hello! This is a test of text to speech."
    @State private var showModelManager = false

    init() {
        let manager = MultiLanguageTtsManager()
        _ttsManager = StateObject(wrappedValue: manager)
        _modelManager = StateObject(wrappedValue: manager.modelManager)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Language selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Language.allCases, id: \.self) { language in
                            LanguageButton(
                                language: language,
                                isSelected: ttsManager.currentLanguage == language,
                                isDownloaded: modelManager.isModelDownloaded(language)
                            ) {
                                ttsManager.switchLanguage(language)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

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
                    .frame(height: 120)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal)

                // Speak button
                Button {
                    if modelManager.isModelDownloaded(ttsManager.currentLanguage) {
                        ttsManager.synthesizeText(inputText, voiceId: selectedVoice, speed: speechSpeed)
                    }
                } label: {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                        Text("Speak")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        modelManager.isModelDownloaded(ttsManager.currentLanguage) ?
                        Color.blue : Color.gray
                    )
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(!modelManager.isModelDownloaded(ttsManager.currentLanguage))
                .padding(.horizontal)

                // Status
                Text(ttsManager.status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Multi-Language TTS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showModelManager = true
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
            }
            .sheet(isPresented: $showModelManager) {
                ModelManagerView(modelManager: modelManager, ttsManager: ttsManager)
            }
        }
    }
}

struct LanguageButton: View {
    let language: Language
    let isSelected: Bool
    let isDownloaded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(language.flag)
                    .font(.system(size: 32))

                Text(language.rawValue)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)

                if !isDownloaded {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .frame(width: 80, height: 80)
            .background(
                isSelected ?
                Color.blue.opacity(0.2) :
                    Color.gray.opacity(0.1)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .disabled(!isDownloaded)
    }
}

struct ModelManagerView: View {
    @ObservedObject var modelManager: ModelDownloadManager
    @ObservedObject var ttsManager: MultiLanguageTtsManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(Language.allCases, id: \.self) { language in
                    ModelRow(
                        language: language,
                        modelManager: modelManager,
                        ttsManager: ttsManager
                    )
                }
            }
            .navigationTitle("Manage Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ModelRow: View {
    let language: Language
    @ObservedObject var modelManager: ModelDownloadManager
    @ObservedObject var ttsManager: MultiLanguageTtsManager

    var body: some View {
        HStack {
            Text(language.flag)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(language.rawValue)
                    .font(.headline)

                Text(language.estimatedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let status = modelManager.downloadStatus[language] {
                    switch status {
                    case .notDownloaded:
                        Text("Not downloaded")
                            .font(.caption)
                            .foregroundColor(.orange)
                    case .downloading:
                        if let progress = modelManager.downloadProgress[language] {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                            Text("\(Int(progress * 100))%")
                                .font(.caption2)
                        }
                    case .downloaded:
                        Text("Downloaded")
                            .font(.caption)
                            .foregroundColor(.green)
                    case .failed(let error):
                        Text("Failed: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            Spacer()

            if modelManager.downloadStatus[language] == .downloaded {
                Button(role: .destructive) {
                    modelManager.deleteModel(for: language)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            } else if modelManager.downloadStatus[language] != .downloading {
                Button {
                    modelManager.downloadModel(for: language) { success, error in
                        if success {
                            ttsManager.switchLanguage(language, downloadIfNeeded: false)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
