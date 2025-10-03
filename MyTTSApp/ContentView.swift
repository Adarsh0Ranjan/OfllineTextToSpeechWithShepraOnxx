
import SwiftUI

struct ContentView: View {
    @StateObject private var ttsManager = MultiLanguageTtsManager()
    @State private var selectedVoice: Int32 = 0
    @State private var speechSpeed: Float = 1.0

    // A dictionary to hold the simple, 3-line text for each language
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
        """
    ]

    // Initialize inputText directly with the default English text. This is simpler and more reliable.
    @State private var inputText = """
    Hello, this is a test of the text-to-speech system.
    I am speaking in English.
    Have a great day!
    """

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
                // Update the inputText to the sample text for the new language
                inputText = sampleTexts[newLang] ?? ""
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
                .frame(height: 120) // Adjusted height for 3 lines
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
