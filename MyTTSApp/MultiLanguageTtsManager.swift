//
//  MultiLanguageTtsManager.swift
//  MyTTSApp
//
//  Created by Adarsh Ranjan on 03/10/25.
//

import Foundation
import AVFoundation
import Combine

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

                        tts = SherpaOnnxCreateOfflineTts(&ttsConfig)
                    }
                }
            }

        case .arabic:
            // VITS Piper model for Arabic
            guard let modelURL = Bundle.main.url(forResource: "model_arabic", withExtension: "onnx"),
                  let tokensURL = Bundle.main.url(forResource: "tokens_arabic", withExtension: "txt") else {
                print("❌ Arabic: Files not found")
                return false
            }

            let modelPath = modelURL.path
            let tokensPath = tokensURL.path

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

                        tts = SherpaOnnxCreateOfflineTts(&ttsConfig)
                    }
                }
            }
        case .chinese:
            // VITS MeloTTS model (end-to-end, no espeak-ng)
            guard let modelURL = Bundle.main.url(forResource: "model_chinese", withExtension: "onnx"),
                  let tokensURL = Bundle.main.url(forResource: "tokens_chinese", withExtension: "txt"),
                  let lexiconURL = Bundle.main.url(forResource: "lexicon_chinese", withExtension: "txt") else {
                print("❌ Chinese: A required file (model, tokens, or lexicon) was not found.")
                return false
            }

            // Get the path to the 'dict_chinese' directory from the main bundle resource path
            guard let resourcePath = Bundle.main.resourceURL else {
                print("❌ Chinese: Failed to get resource path")
                return false
            }
            let dictDirURL = resourcePath.appendingPathComponent("dict_chinese")

            // Verify the directory exists
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dictDirURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                print("❌ Chinese: The 'dict_chinese' directory was not found in your app bundle.")
                return false
            }

            let modelPath = modelURL.path
            let tokensPath = tokensURL.path
            let lexiconPath = lexiconURL.path
            let dictDirPath = dictDirURL.path

            // Note: data_dir is nil because this model does not use espeak-ng
            modelPath.withCString { cModelPath in
                tokensPath.withCString { cTokensPath in
                    lexiconPath.withCString { cLexiconPath in
                        dictDirPath.withCString { cDictDirPath in
                            var vitsConfig = SherpaOnnxOfflineTtsVitsModelConfig(
                                model: cModelPath,
                                lexicon: cLexiconPath,
                                tokens: cTokensPath,
                                data_dir: nil, // NO espeak-ng-data needed
                                noise_scale: 0.667,
                                noise_scale_w: 0.8,
                                length_scale: 1.0,
                                dict_dir: cDictDirPath // Path to the Jieba dictionary
                            )

                            var modelConfig = SherpaOnnxOfflineTtsModelConfig(
                                vits: vitsConfig,
                                num_threads: 2,
                                debug: 1, // Use 1 for debugging if it crashes
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
            if currentLanguage == .chinese {
                player.volume = 18
            }
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
