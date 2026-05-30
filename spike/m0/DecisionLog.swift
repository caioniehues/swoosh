import Foundation

/// Append-only JSONL decision/measurement log.
///
/// Every probe writes structured lines (one JSON object per line) so a matrix
/// run is auditable and can be aggregated into `RESULTS.md` (U6). Writes are
/// serialized on a private queue; lines are also echoed to stdout for live runs.
final class DecisionLog {
    private let url: URL
    private let queue = DispatchQueue(label: "swoosh.m0.log")

    init(path: String) {
        self.url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
    }

    /// Record one event with arbitrary JSON-serializable fields.
    func record(_ event: String, _ fields: [String: Any] = [:]) {
        var object: [String: Any] = [
            "event": event,
            "t": Date().timeIntervalSince1970,
        ]
        for (key, value) in fields { object[key] = value }

        queue.sync {
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object),
                  let line = String(data: data, encoding: .utf8) else { return }
            print(line)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let bytes = (line + "\n").data(using: .utf8) { handle.write(bytes) }
                try? handle.close()
            }
        }
    }
}
