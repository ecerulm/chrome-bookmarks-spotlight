import Foundation
import AppKit

/// Reads Chrome's local favicon database without modifying or locking it.
final class ChromeFavicons {
    private let connection: OpaquePointer?

    init(profile: String) {
        let path = ChromeBookmarksReader.chromeUserDataDir
            .appendingPathComponent(profile, isDirectory: true)
            .appendingPathComponent("Favicons")
            .path

        var connection: OpaquePointer?
        if sqlite3_open_v2(path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) != SQLITE_OK {
            if let connection { sqlite3_close(connection) }
            self.connection = nil
        } else {
            sqlite3_busy_timeout(connection, 1_000)
            self.connection = connection
        }
    }

    func data(for url: URL) -> Data? {
        guard let connection else { return nil }

        let query = """
            SELECT fb.image_data
            FROM icon_mapping im
            JOIN favicon_bitmaps fb ON fb.icon_id = im.icon_id
            WHERE im.page_url = ?1
            ORDER BY LENGTH(im.page_url) DESC, fb.width DESC
            LIMIT 1
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let urlString = url.absoluteString
        sqlite3_bind_text(statement, 1, urlString, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0) else {
            return nil
        }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }

    static func fetchFromNetwork(for url: URL, completion: @escaping (Data?) -> Void) {
        guard let host = url.host else {
            completion(nil)
            return
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = url.port
        components.path = "/favicon.ico"
        guard let faviconURL = components.url else {
            completion(nil)
            return
        }

        var request = URLRequest(url: faviconURL)
        request.timeoutInterval = 5
        request.setValue("ChromeBookmarksSpotlight/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  NSImage(data: data) != nil else {
                completion(nil)
                return
            }
            completion(data)
        }.resume()
    }

    static func cachedData(for url: URL) -> Data? {
        let file = cacheURL(for: url)
        guard let data = try? Data(contentsOf: file), NSImage(data: data) != nil else {
            return nil
        }
        return data
    }

    static func cache(data: Data, for url: URL) {
        let file = cacheURL(for: url)
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: file, options: .atomic)
        } catch {
            // A cache failure should never prevent a bookmark from indexing.
        }
    }

    private static func cacheURL(for url: URL) -> URL {
        let cacheDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChromeBookmarksSpotlight/Favicons", isDirectory: true)
        let key = Data(url.absoluteString.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return cacheDirectory.appendingPathComponent(key).appendingPathExtension("icon")
    }

    deinit {
        if let connection { sqlite3_close(connection) }
    }
}

private let SQLITE_OK: Int32 = 0
private let SQLITE_ROW: Int32 = 100
private let SQLITE_OPEN_READONLY: Int32 = 0x00000001
private let SQLITE_OPEN_URI: Int32 = 0x00000040
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private typealias sqlite3_destructor_type = @convention(c) (UnsafeMutableRawPointer?) -> Void

@_silgen_name("sqlite3_open_v2")
private func sqlite3_open_v2(
    _ filename: UnsafePointer<CChar>?,
    _ database: UnsafeMutablePointer<OpaquePointer?>?,
    _ flags: Int32,
    _ vfs: UnsafePointer<CChar>?
) -> Int32

@_silgen_name("sqlite3_close")
private func sqlite3_close(_ database: OpaquePointer?) -> Int32

@_silgen_name("sqlite3_prepare_v2")
private func sqlite3_prepare_v2(
    _ database: OpaquePointer?,
    _ sql: UnsafePointer<CChar>?,
    _ length: Int32,
    _ statement: UnsafeMutablePointer<OpaquePointer?>?,
    _ tail: UnsafeMutablePointer<UnsafePointer<CChar>?>?
) -> Int32

@_silgen_name("sqlite3_finalize")
private func sqlite3_finalize(_ statement: OpaquePointer?) -> Int32

@_silgen_name("sqlite3_bind_text")
private func sqlite3_bind_text(
    _ statement: OpaquePointer?,
    _ index: Int32,
    _ value: UnsafePointer<CChar>?,
    _ length: Int32,
    _ destructor: sqlite3_destructor_type?
) -> Int32

@_silgen_name("sqlite3_step")
private func sqlite3_step(_ statement: OpaquePointer?) -> Int32

@_silgen_name("sqlite3_busy_timeout")
private func sqlite3_busy_timeout(_ database: OpaquePointer?, _ milliseconds: Int32) -> Int32

@_silgen_name("sqlite3_column_blob")
private func sqlite3_column_blob(_ statement: OpaquePointer?, _ column: Int32) -> UnsafeRawPointer?

@_silgen_name("sqlite3_column_bytes")
private func sqlite3_column_bytes(_ statement: OpaquePointer?, _ column: Int32) -> Int32
