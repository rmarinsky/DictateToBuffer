import Foundation

struct ReleaseHighlights: Decodable, Equatable {
    let schemaVersion: Int
    let headline: String
    let highlights: [String]
}
