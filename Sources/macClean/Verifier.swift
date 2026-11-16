import Foundation

/// 视频工程核对：本地视频在 OneDrive 里有没有一模一样的一份。只读。
/// OneDrive 那份如果只在云端（dataless），不下载，只比大小。
enum VerifyStatus: Sendable {
    case identical(String)        // 逐字节一致，附 OneDrive 路径
    case sizeOnly(String)         // 大小一致，但云端那份没下载，没逐字节比较
    case differs                  // 有同样大小的文件，但内容不同
    case missing                  // OneDrive 里找不到

    var isSafe: Bool { if case .identical = self { true } else { false } }
}

struct VideoCheck: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let size: Int64
    let status: VerifyStatus
}

struct VerifyReport: Sendable {
    let checks: [VideoCheck]
    var identical: Int { checks.filter { $0.status.isSafe }.count }
    var sizeOnly: Int { checks.filter { if case .sizeOnly = $0.status { true } else { false } }.count }
    var localOnly: Int { checks.count - identical - sizeOnly }
    var localOnlyBytes: Int64 {
        checks.filter { if case .missing = $0.status { true } else if case .differs = $0.status { true } else { false } }
            .reduce(0) { $0 + $1.size }
    }
}

enum Verifier {
    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm"]
    static let minSize: Int64 = 5 << 20

    /// OneDrive 里所有视频：大小 → 路径
    static func oneDriveIndex() -> [Int64: [String]] {
        var idx: [Int64: [String]] = [:]
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: Detectors.oneDriveRoot),
                                                     includingPropertiesForKeys: Array(keys), options: [],
                                                     errorHandler: { _, _ in true }) else { return idx }
        for case let u as URL in e where videoExts.contains(u.pathExtension.lowercased()) {
            guard let v = try? u.resourceValues(forKeys: keys), v.isRegularFile == true,
                  let s = v.fileSize, Int64(s) >= minSize else { continue }
            idx[Int64(s), default: []].append(u.path)
        }
        return idx
    }

    static func verify(_ dir: String, index: [Int64: [String]]) -> VerifyReport {
        var checks: [VideoCheck] = []
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        let e = FileManager.default.enumerator(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: Array(keys),
                                               options: [], errorHandler: { _, _ in true })
        while let u = e?.nextObject() as? URL {
            guard videoExts.contains(u.pathExtension.lowercased()),
                  let v = try? u.resourceValues(forKeys: keys), v.isRegularFile == true,
                  let s = v.fileSize, Int64(s) >= minSize else { continue }
            let size = Int64(s)
            var status = VerifyStatus.missing
            for cand in index[size] ?? [] {
                if isDataless(cand) {
                    if case .missing = status { status = .sizeOnly(cand) }
                    continue
                }
                if sameBytes(u.path, cand) { status = .identical(cand); break }
                if case .missing = status { status = .differs }
            }
            checks.append(VideoCheck(path: u.path, size: size, status: status))
        }
        checks.sort { $0.size > $1.size }
        return VerifyReport(checks: checks)
    }

    static func isDataless(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return st.st_flags & 0x4000_0000 != 0   // SF_DATALESS
    }

    /// 分块逐字节比较
    static func sameBytes(_ a: String, _ b: String) -> Bool {
        guard let ha = FileHandle(forReadingAtPath: a), let hb = FileHandle(forReadingAtPath: b) else { return false }
        defer { try? ha.close(); try? hb.close() }
        let chunk = 8 << 20
        while true {
            let da = ha.readData(ofLength: chunk)
            let db = hb.readData(ofLength: chunk)
            if da != db { return false }
            if da.isEmpty { return true }
        }
    }
}
