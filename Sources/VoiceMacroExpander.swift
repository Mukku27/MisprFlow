import Foundation

struct VoiceMacro: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var command: String
    var payload: String
}

enum VoiceMacroExpansion: Equatable {
    case whole(command: String, payload: String)
    case inline(expandedText: String, commands: [String], payloads: [String])
    case none
}

enum VoiceMacroExpander {
    static func normalize(_ text: String) -> String {
        let lowercased = text.lowercased()
        let stripped = lowercased.components(separatedBy: CharacterSet.punctuationCharacters).joined()
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func expand(transcript: String, macros: [VoiceMacro]) -> VoiceMacroExpansion {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        struct PreparedMacro {
            let command: String
            let payload: String
            let words: [String]
        }
        var prepared: [PreparedMacro] = []
        prepared.reserveCapacity(macros.count)
        for macro in macros {
            let normalizedCommand = normalize(macro.command)
            guard !normalizedCommand.isEmpty else { continue }
            let words = normalizedCommand.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard !words.isEmpty else { continue }
            prepared.append(PreparedMacro(command: macro.command, payload: macro.payload, words: words))
        }
        guard !prepared.isEmpty else { return .none }

        let normalizedTranscript = normalize(trimmed)
        guard !normalizedTranscript.isEmpty else { return .none }
        let transcriptWords = normalizedTranscript.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !transcriptWords.isEmpty else { return .none }

        for candidate in prepared {
            if transcriptWords == candidate.words {
                return .whole(command: candidate.command, payload: candidate.payload)
            }
        }

        struct Token {
            let normalized: String
            let coreRange: Range<String.Index>?
        }
        var tokens: [Token] = []
        var cursor = trimmed.startIndex
        while cursor < trimmed.endIndex {
            while cursor < trimmed.endIndex && trimmed[cursor].isWhitespace {
                cursor = trimmed.index(after: cursor)
            }
            guard cursor < trimmed.endIndex else { break }
            let tokenStart = cursor
            while cursor < trimmed.endIndex && !trimmed[cursor].isWhitespace {
                cursor = trimmed.index(after: cursor)
            }
            let tokenEnd = cursor
            let tokenText = String(trimmed[tokenStart..<tokenEnd])
            let normalizedToken = normalize(tokenText)
            let core = coreRange(in: trimmed, tokenRange: tokenStart..<tokenEnd)
            tokens.append(Token(normalized: normalizedToken, coreRange: core))
        }

        var words: [String] = []
        var wordTokenIndices: [Int] = []
        words.reserveCapacity(tokens.count)
        wordTokenIndices.reserveCapacity(tokens.count)
        for (tokenIndex, token) in tokens.enumerated() {
            guard !token.normalized.isEmpty else { continue }
            words.append(token.normalized)
            wordTokenIndices.append(tokenIndex)
        }
        guard !words.isEmpty else { return .none }

        struct InlineMatch {
            let wordStart: Int
            let wordEnd: Int
            let command: String
            let payload: String
        }
        var matches: [InlineMatch] = []
        var wordIndex = 0
        while wordIndex < words.count {
            var best: PreparedMacro?
            var bestLength = 0
            for candidate in prepared {
                let length = candidate.words.count
                guard length > 0, wordIndex + length <= words.count else { continue }
                guard length > bestLength else { continue }
                var matchesWords = true
                for offset in 0..<length {
                    if words[wordIndex + offset] != candidate.words[offset] {
                        matchesWords = false
                        break
                    }
                }
                if matchesWords {
                    best = candidate
                    bestLength = length
                }
            }
            if let found = best {
                matches.append(InlineMatch(
                    wordStart: wordIndex,
                    wordEnd: wordIndex + bestLength,
                    command: found.command,
                    payload: found.payload
                ))
                wordIndex += bestLength
            } else {
                wordIndex += 1
            }
        }
        guard !matches.isEmpty else { return .none }

        struct Replacement {
            let span: Range<String.Index>
            let command: String
            let payload: String
        }
        var replacements: [Replacement] = []
        replacements.reserveCapacity(matches.count)
        for match in matches {
            let firstTokenIndex = wordTokenIndices[match.wordStart]
            let lastTokenIndex = wordTokenIndices[match.wordEnd - 1]
            guard let firstCore = tokens[firstTokenIndex].coreRange,
                  let lastCore = tokens[lastTokenIndex].coreRange else {
                continue
            }
            replacements.append(Replacement(
                span: firstCore.lowerBound..<lastCore.upperBound,
                command: match.command,
                payload: match.payload
            ))
        }
        guard !replacements.isEmpty else { return .none }

        var expanded = trimmed
        for replacement in replacements.reversed() {
            expanded.replaceSubrange(replacement.span, with: replacement.payload)
        }
        return .inline(
            expandedText: expanded,
            commands: replacements.map { $0.command },
            payloads: replacements.map { $0.payload }
        )
    }

    static func containsAllPayloads(_ text: String, payloads: [String]) -> Bool {
        var expectedCounts: [String: Int] = [:]
        for payload in payloads {
            guard !payload.isEmpty else { continue }
            expectedCounts[payload, default: 0] += 1
        }
        for (payload, expected) in expectedCounts {
            if occurrences(of: payload, in: text) < expected {
                return false
            }
        }
        return true
    }

    static func restoredTranscript(
        cleaned: String,
        expandedFallback: String,
        payloads: [String]
    ) -> String {
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "EMPTY" {
            return expandedFallback
        }
        if containsAllPayloads(cleaned, payloads: payloads) {
            return cleaned
        }
        return expandedFallback
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, options: [], range: searchRange) {
            count += 1
            searchRange = found.upperBound..<haystack.endIndex
        }
        return count
    }

    private static func coreRange(in text: String, tokenRange: Range<String.Index>) -> Range<String.Index>? {
        var start = tokenRange.lowerBound
        var end = tokenRange.upperBound
        while start < end {
            let ch = text[start]
            if ch.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }) {
                start = text.index(after: start)
            } else {
                break
            }
        }
        while end > start {
            let prev = text.index(before: end)
            let ch = text[prev]
            if ch.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }) {
                end = prev
            } else {
                break
            }
        }
        guard start < end else { return nil }
        return start..<end
    }
}
