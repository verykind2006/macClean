import Foundation

/// Codex 对话数据库整理：按「整个对话」删除最后活动早于 N 天的记录，再压缩并做完整性检查。
/// 只能在 Codex 后台服务退出后执行（由 Prechecks 的 codex-stopped 把关）。
enum CodexTrim {
    static let sqlite = "/usr/bin/sqlite3"

    static func cutoffMs(days: Double) -> Int64 {
        Int64((Date().timeIntervalSince1970 - days * 86_400) * 1000)
    }

    /// 只读估算：(要删的对话数, 这些对话的内容字节数, 对话总数)
    static func estimate(_ db: String, days: Double) -> (threads: Int, bytes: Int64, total: Int)? {
        let c = cutoffMs(days: days)
        let sql = """
        WITH last AS (SELECT thread_id, max(created_at_ms) m FROM thread_items GROUP BY thread_id),
             old AS (SELECT thread_id FROM last WHERE m < \(c))
        SELECT (SELECT count(*) FROM old),
               (SELECT coalesce(sum(length(item_json)), 0) FROM thread_items WHERE thread_id IN (SELECT thread_id FROM old)),
               (SELECT count(*) FROM last);
        """
        // 先按只读打开；WAL 库缺 -shm 时只读打不开，退一步用 immutable（只读快照，不加锁）
        var r = Shell.run(sqlite, ["-readonly", "file:\(db)?mode=ro", sql])
        if r.status != 0 || r.output.contains("Error") {
            r = Shell.run(sqlite, ["-readonly", "file:\(db)?mode=ro&immutable=1", sql])
        }
        guard r.status == 0 else { return nil }
        let parts = r.output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|")
        guard parts.count == 3, let a = Int(parts[0]), let b = Int64(parts[1]), let t = Int(parts[2]) else { return nil }
        return (a, b, t)
    }

    static func run(_ db: String, days: Double) -> Outcome {
        let before = fileSize(db)
        let c = cutoffMs(days: days)
        let sql = """
        PRAGMA busy_timeout = 5000;
        BEGIN IMMEDIATE;
        CREATE TEMP TABLE old_threads AS
          SELECT thread_id FROM (SELECT thread_id, max(created_at_ms) m FROM thread_items GROUP BY thread_id) WHERE m < \(c);
        DELETE FROM thread_items WHERE thread_id IN (SELECT thread_id FROM old_threads);
        DELETE FROM thread_turns WHERE thread_id IN (SELECT thread_id FROM old_threads);
        DELETE FROM thread_realtime_items WHERE thread_id IN (SELECT thread_id FROM old_threads);
        DELETE FROM thread_history_projection_state WHERE thread_id IN (SELECT thread_id FROM old_threads);
        SELECT 'deleted:' || (SELECT count(*) FROM old_threads);
        COMMIT;
        PRAGMA wal_checkpoint(TRUNCATE);
        VACUUM;
        PRAGMA integrity_check;
        """
        let r = Shell.run(sqlite, [db, sql])
        let lines = r.output.split(separator: "\n").map(String.init)
        guard r.status == 0 else {
            return .failed("sqlite3 出错：\(lines.suffix(2).joined(separator: " "))")
        }
        guard lines.last == "ok" else {
            return .failed("完整性检查没通过：\(lines.suffix(3).joined(separator: " "))")
        }
        let deleted = lines.first { $0.hasPrefix("deleted:") }?.dropFirst(8) ?? "?"
        let after = fileSize(db)
        return .done("删了 \(deleted) 个对话；数据库 \(Fmt.bytes(before)) → \(Fmt.bytes(after))；完整性检查通过")
    }

    static func fileSize(_ p: String) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: p))?[.size] as? Int64) ?? 0
    }
}
