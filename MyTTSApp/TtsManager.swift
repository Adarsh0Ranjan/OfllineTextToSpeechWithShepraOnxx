////
////  TtsManager.swift
////  MyTTSApp
////
////  Created by Adarsh Ranjan on 02/10/25.
////
//
//
//import SwiftUI
//import AVFoundation
//import Combine
//
//class TtsManager: ObservableObject {
//    @Published var status: String = "Ready"
//    @Published var availableVoices: [Int32] = []
//
//    private var audioEngine: AVAudioEngine?
//    private var playerNode: AVAudioPlayerNode?
//    private var tts: OpaquePointer?
//    private var isInitialized = false
//    private var isPlayerConnected = false
//
//    init() {
//        setupAudioEngine()
//        initializeTTS()
//    }
//
//    private func setupAudioEngine() {
//        audioEngine = AVAudioEngine()
//        playerNode = AVAudioPlayerNode()
//        guard let engine = audioEngine, let player = playerNode else { return }
//        engine.attach(player)
//    }
//
//    private func initializeTTS() {
//        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//            guard let self = self else { return }
//
//            DispatchQueue.main.async { self.status = "Loading Kokoro model..." }
//
//            // --- 1. Updated File Paths for the Kokoro Model ---
//            let modelSubdirectory = "english/kokoro-en-v0_19"
//            
//            let modelURL = Bundle.main.url(forResource: "model", withExtension: "onnx", subdirectory: modelSubdirectory)
//            let tokensURL = Bundle.main.url(forResource: "tokens", withExtension: "txt", subdirectory: modelSubdirectory)
//            let voicesURL = Bundle.main.url(forResource: "voices", withExtension: "json", subdirectory: modelSubdirectory)
//            let lexiconURL = Bundle.main.url(forResource: "lexicon", withExtension: "txt", subdirectory: modelSubdirectory)
//            
//            guard let resourcePath = Bundle.main.resourceURL else {
//                DispatchQueue.main.async { self.status = "Failed to get resource path" }
//                return
//            }
//
//            // Paths for directories
//            let espeakDataURL = resourcePath.appendingPathComponent("espeak-ng-data")
//            let dictDirURL = resourcePath.appendingPathComponent(modelSubdirectory).appendingPathComponent("dict")
//
//            // Check for missing files and directories
//            var missingFiles: [String] = []
//            if modelURL == nil { missingFiles.append("model.onnx") }
//            if tokensURL == nil { missingFiles.append("tokens.txt") }
//            if voicesURL == nil { missingFiles.append("voices.json") }
//            if lexiconURL == nil { missingFiles.append("lexicon.txt") }
//
//            var isDirectory: ObjCBool = false
//            if !FileManager.default.fileExists(atPath: espeakDataURL.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
//                missingFiles.append("espeak-ng-data directory")
//            }
//            if !FileManager.default.fileExists(atPath: dictDirURL.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
//                missingFiles.append("dict directory")
//            }
//
//            if !missingFiles.isEmpty {
//                DispatchQueue.main.async {
//                    self.status = "Missing: \(missingFiles.joined(separator: ", "))"
//                }
//                return
//            }
//
//            let modelPath = modelURL!.path
//            let tokensPath = tokensURL!.path
//            let voicesPath = voicesURL!.path
//            let lexiconPath = lexiconURL!.path
//            let espeakDataPath = espeakDataURL.path
//            let dictDirPath = dictDirURL.path
//            let lang = "en_US" // Language for Kokoro model
//
//            // --- 2. Correctly Initialize Kokoro Config with ALL Parameters ---
//            lang.withCString { cLang in
//                dictDirPath.withCString { cDictDirPath in
//                    lexiconPath.withCString { cLexiconPath in
//                        espeakDataPath.withCString { cEspeakDataPath in
//                            modelPath.withCString { cModelPath in
//                                tokensPath.withCString { cTokensPath in
//                                    voicesPath.withCString { cVoicesPath in
//
//                                        var kokoroConfig = SherpaOnnxOfflineTtsKokoroModelConfig(
//                                            model: cModelPath,
//                                            voices: cVoicesPath,
//                                            tokens: cTokensPath,
//                                            data_dir: cEspeakDataPath,
//                                            length_scale: 1.0,
//                                            dict_dir: cDictDirPath, // Added
//                                            lexicon: cLexiconPath,   // Added
//                                            lang: cLang              // Added
//                                        )
//
//                                        var modelConfig = SherpaOnnxOfflineTtsModelConfig(
//                                            vits: SherpaOnnxOfflineTtsVitsModelConfig(),
//                                            num_threads: 2,
//                                            debug: 0,
//                                            provider: "cpu",
//                                            matcha: SherpaOnnxOfflineTtsMatchaModelConfig(),
//                                            kokoro: kokoroConfig, // Set the .kokoro property
//                                            kitten: SherpaOnnxOfflineTtsKittenModelConfig(),
//                                            zipvoice: SherpaOnnxOfflineTtsZipvoiceModelConfig()
//                                        )
//
//                                        var ttsConfig = SherpaOnnxOfflineTtsConfig(
//                                            model: modelConfig,
//                                            rule_fsts: nil,
//                                            max_num_sentences: 1,
//                                            rule_fars: nil,
//                                            silence_scale: 0.5
//                                        )
//
//                                        self.tts = SherpaOnnxCreateOfflineTts(&ttsConfig)
//
//                                        if self.tts != nil {
//                                            self.isInitialized = true
//                                            let numSpeakers = SherpaOnnxOfflineTtsNumSpeakers(self.tts)
//                                            print("Available speakers: \(numSpeakers)")
//
//                                            DispatchQueue.main.async {
//                                                self.availableVoices = Array(0..<numSpeakers)
//                                                self.status = "Ready - \(numSpeakers) voices available"
//                                            }
//                                        } else {
//                                            DispatchQueue.main.async {
//                                                self.status = "Failed to initialize TTS"
//                                            }
//                                        }
//                                    }
//                                }
//                            }
//                        }
//                    }
//                }
//            }
//        }
//    }
//
//    // ... (The rest of your TtsManager class remains the same) ...
//    // synthesizeText, playAudioStream, and deinit methods are correct.
//    
//    func synthesizeText(_ text: String, voiceId: Int32 = 0, speed: Float = 1.0) {
//        guard isInitialized, let tts = tts else {
//            status = "TTS not initialized"
//            return
//        }
//
//        DispatchQueue.main.async {
//            self.status = "Synthesizing with voice \(voiceId)..."
//        }
//
//        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
//            .map { $0.trimmingCharacters(in: .whitespaces) }
//            .filter { !$0.isEmpty }
//
//        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//            guard let self = self else { return }
//
//            let startTime = Date()
//
//            for (index, sentence) in sentences.enumerated() {
//                if sentence.isEmpty { continue }
//
//                guard let generatedAudio = SherpaOnnxOfflineTtsGenerate(tts, sentence, voiceId, speed) else {
//                    continue
//                }
//
//                let sampleCount = generatedAudio.pointee.n
//                let sampleRate = generatedAudio.pointee.sample_rate
//
//                if let samples = generatedAudio.pointee.samples {
//                    self.playAudioStream(from: samples, count: Int(sampleCount), sampleRate: sampleRate)
//
//                    if index == 0 {
//                        let latency = Date().timeIntervalSince(startTime)
//                        DispatchQueue.main.async {
//                            self.status = "Voice \(voiceId) (latency: \(String(format: "%.2f", latency))s)"
//                        }
//                    }
//                }
//
//                SherpaOnnxDestroyOfflineTtsGeneratedAudio(generatedAudio)
//            }
//
//            DispatchQueue.main.async {
//                self.status = "Ready - \(self.availableVoices.count) voices available"
//            }
//        }
//    }
//
//    private func playAudioStream(from samples: UnsafePointer<Float>, count: Int, sampleRate: Int32) {
//        guard let player = playerNode, let engine = audioEngine else { return }
//
//        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
//
//        if !isPlayerConnected {
//            engine.connect(player, to: engine.mainMixerNode, format: format)
//            isPlayerConnected = true
//
//            do {
//                try engine.start()
//            } catch {
//                print("Failed to start audio engine: \(error)")
//                return
//            }
//        }
//
//        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(count)) else {
//            return
//        }
//
//        buffer.frameLength = UInt32(count)
//
//        if let channelData = buffer.floatChannelData {
//            for i in 0..<count {
//                channelData[0][i] = samples[i]
//            }
//        }
//
//        player.scheduleBuffer(buffer, completionHandler: nil)
//
//        if !player.isPlaying {
//            player.play()
//        }
//    }
//
//    deinit {
//        if let tts = tts {
//            SherpaOnnxDestroyOfflineTts(tts)
//        }
//        audioEngine?.stop()
//    }
//}
