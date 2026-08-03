import Foundation

struct ReleaseHighlights: Decodable, Equatable {
    let schemaVersion: Int
    let headline: String
    let highlights: [String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, headline, highlights
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        headline = try container.decode(String.self, forKey: .headline)
        highlights = try container.decode([String].self, forKey: .highlights)

        guard schemaVersion == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported release highlights schema"
            )
        }
        guard !headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .headline,
                in: container,
                debugDescription: "Release headline must not be empty"
            )
        }
        guard (1...3).contains(highlights.count),
              highlights.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .highlights,
                in: container,
                debugDescription: "Release highlights must contain one to three non-empty items"
            )
        }
    }
}
