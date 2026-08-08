import Foundation

public enum ClipCodec {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(_ clips: [Clip]) throws -> Data {
        try makeEncoder().encode(clips)
    }

    public static func decode(_ data: Data) throws -> [Clip] {
        try makeDecoder().decode([Clip].self, from: data)
    }
}
