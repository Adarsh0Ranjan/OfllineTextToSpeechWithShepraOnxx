import SwiftUI

struct ContentView: View {
    @StateObject private var ttsManager = MultiLanguageTtsManager()
    @State private var selectedVoice: Int32 = 0
    @State private var speechSpeed: Float = 1.0
    @State private var inputText = "Hello! This is a test."

    // Provide default sample texts per language
    private let sampleTexts: [Language: String] = [
        .english: """
    Hello, this is a test of the text-to-speech system.
    I am speaking in English.
    Have a great day!
    """,
        .french: """
    Bonjour, ceci est un test du système de synthèse vocale.
    Je parle en français.
    Passe une bonne journée!
    """,
        .arabic: """
    مرحباً، هذا اختبار لنظام تحويل النص إلى كلام.
    أنا أتحدث باللغة العربية.
    أتمنى لك يوماً سعيداً!
    """,
        .chinese: """
    你好，这是一个语音合成系统的测试。
    我正在说中文。
    祝你有美好的一天！
    """
    ]

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
                if let sample = sampleTexts[newLang] {
                    inputText = sample
                }
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

            // Speed slider
            VStack(alignment: .leading, spacing: 8) {
                Text("Speed: \(String(format: "%.1f", speechSpeed))x")
                    .font(.headline)
                Slider(value: $speechSpeed, in: 0.5...2.0, step: 0.1)
            }
            .padding(.horizontal)

            // Text editor for input
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

            // Status display
            Text(ttsManager.status)
                .padding()
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }
}
