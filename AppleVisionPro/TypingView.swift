//
//  Typing.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 23.04.25.
//

import SwiftUI

struct TypingView: View {
    
    let targetPhrase = "The quick brown fox jumps over the lazy dog"
    @State private var currentIndex: Int = 0
    @State private var userInput: String = ""
    @State private var mistakeIndices: Set<Int> = []
    @State private var startTime: Date? = nil
    @State private var finishTime: Date? = nil
    @State private var isCompleted: Bool = false
    @FocusState private var isFocused: Bool

    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            
            Button(action: {
                appState.currentPage = .test
            }) {
                Image(systemName: "chevron.backward")
            }
            .clipShape(Circle())
            .offset(x: -580, y: -300)
            
            VStack(spacing: 30) {
                
                Text("Typing Speed Test")
                    .font(.title)
                    .bold()
                
                // Phrase
                HStack{
                    let Phrase = targetPhrase.replacingOccurrences(of: " ", with: "·")
                    ForEach(Array(Phrase.enumerated()), id: \.offset) { index, char in
                        Text(String(char))
                            .underline(index == currentIndex)
                            .font(.system(size: 22, design: .monospaced))
                            .foregroundColor(mistakeIndices.contains(index) && index < currentIndex ? .red : .white)
                            .onTapGesture { isFocused = true }
                    }
                }
                
                // Input
                TextField("", text: $userInput)
                    .focused($isFocused)
                    .frame(width: 0, height: 0)
                    .onChange(of: userInput) {oldValue, newValue in
                        if let inputChar = newValue.last {
                            handleInput(inputChar: inputChar)
                            userInput = ""
                        }
                    }
                    .onAppear{isFocused = true}
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.asciiCapable)
                
                // Results
                if isCompleted {
                    Text("Speed: \(String(format: "%.1f", calculateWPM())) WPM")
                    Text("Accuracy: \(String(format: "%.1f", calculateAccuracy()))%")
                }
            }
        }
    }

    private func handleInput(inputChar: Character) {
        let targetChar = targetPhrase[targetPhrase.index(targetPhrase.startIndex, offsetBy: currentIndex)]
        
        if startTime == nil {
            startTime = Date()
        }

        if inputChar == targetChar {
            currentIndex += 1

            if currentIndex == targetPhrase.count {
                finishTime = Date()
                isCompleted = true
                isFocused = false
            }
        } else {
            mistakeIndices.insert(currentIndex)
        }
    }

    private func calculateWPM() -> Double {
        if startTime != nil && finishTime != nil {
            let timeInMinutes = finishTime!.timeIntervalSince(startTime!) / 60
            let wordCount = targetPhrase.split(separator: " ").count
            return Double(wordCount) / timeInMinutes
        } else {
            return 0
        }
    }

    private func calculateAccuracy() -> Double {
        let correctCharacters = targetPhrase.count - mistakeIndices.count
        return (Double(correctCharacters) / Double(targetPhrase.count)) * 100
    }
}
