import Foundation
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite)
import CSQLite
#endif
import SwiftTUI

// MARK: - Schema & Query Result Models

public struct SQLColumnInfo: Equatable, Hashable, Sendable {
    public let cid: Int
    public let name: String
    public let type: String
    public let notNull: Bool
    public let defaultValue: String?
    public let isPrimaryKey: Bool

    public var summaryBadge: String {
        var parts: [String] = []
        if !type.isEmpty { parts.append(type) }
        if isPrimaryKey { parts.append("PK") }
        else if notNull { parts.append("NN") }
        return parts.joined(separator: " ")
    }
}

public struct SQLForeignKeyInfo: Equatable, Hashable, Sendable {
    public let fromColumn: String
    public let targetTable: String
    public let targetColumn: String
}

public struct SQLTableSchema: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let kind: String // "table" or "view"
    public let ddl: String
    public let columns: [SQLColumnInfo]
    public let foreignKeys: [SQLForeignKeyInfo]
    public let rowCount: Int

    public var primaryKeyColumnIndex: Int? {
        columns.firstIndex(where: \.isPrimaryKey)
    }
}

public struct SQLIndexInfo: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let tableName: String
    public let ddl: String
}

public struct SQLTriggerInfo: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let tableName: String
    public let ddl: String
}

public struct SQLDatabaseSchema: Equatable, Sendable {
    public let databasePath: String
    public let sqliteVersion: String
    public let tables: [SQLTableSchema]
    public let views: [SQLTableSchema]
    public let indexes: [SQLIndexInfo]
    public let triggers: [SQLTriggerInfo]

    public var allRelations: [SQLTableSchema] {
        tables + views
    }

    public func relation(named name: String) -> SQLTableSchema? {
        let lower = name.lowercased()
        return allRelations.first { $0.name.lowercased() == lower }
    }
}

public struct SQLQueryResult: Equatable, Sendable {
    public let sql: String
    public let columns: [String]
    public let rows: [[String?]]
    public let rowsAffected: Int
    public let executionTimeMs: Double
    public let error: String?

    public var isSuccess: Bool { error == nil }
}

// MARK: - SQLiteDatabase Engine

/// Wrapper around system `libsqlite3` providing schema introspection, query execution, query plan inspection, and demo seeding.
public final class SQLiteDatabase {
    public let path: String
    private var db: OpaquePointer?

    public init(path: String = ":memory:", seedDemoIfEmpty: Bool = true) throws {
        self.path = path
        var handle: OpaquePointer?
        let rc = sqlite3_open(path, &handle)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open SQLite database"
            if let handle { sqlite3_close(handle) }
            throw NSError(domain: "SQLiteDatabase", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: msg])
        }
        self.db = handle
        _ = execute("PRAGMA foreign_keys = ON;")

        if seedDemoIfEmpty {
            let existingTables = querySingleColumn("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
            if existingTables.isEmpty {
                seedDemoSchemaAndData()
            }
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Query Execution

    @discardableResult
    public func execute(_ sql: String) -> SQLQueryResult {
        guard let db else {
            return SQLQueryResult(sql: sql, columns: [], rows: [], rowsAffected: 0, executionTimeMs: 0, error: "Database closed")
        }

        let startTime = DispatchTime.now().uptimeNanoseconds
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SQLQueryResult(sql: sql, columns: [], rows: [], rowsAffected: 0, executionTimeMs: 0, error: nil)
        }

        var stmt: OpaquePointer?
        var tail: UnsafePointer<CChar>?
        var lastColumns: [String] = []
        var lastRows: [[String?]] = []
        var totalAffected = 0

        let remainingCString = trimmed.utf8CString
        let resultError: String? = remainingCString.withUnsafeBufferPointer { buf -> String? in
            guard var currentPtr = buf.baseAddress else { return nil }
            while currentPtr.pointee != 0 {
                // Skip leading whitespace/semicolons
                while currentPtr.pointee != 0 && (currentPtr.pointee == 32 || currentPtr.pointee == 10 || currentPtr.pointee == 13 || currentPtr.pointee == 9 || currentPtr.pointee == 59) {
                    currentPtr = currentPtr.advanced(by: 1)
                }
                if currentPtr.pointee == 0 { break }

                let prepRC = sqlite3_prepare_v2(db, currentPtr, -1, &stmt, &tail)
                guard prepRC == SQLITE_OK else {
                    let err = String(cString: sqlite3_errmsg(db))
                    if let stmt { sqlite3_finalize(stmt) }
                    return err
                }

                guard let activeStmt = stmt else {
                    if let tail { currentPtr = tail } else { break }
                    continue
                }

                let colCount = Int(sqlite3_column_count(activeStmt))
                var cols: [String] = []
                for c in 0..<colCount {
                    if let cName = sqlite3_column_name(activeStmt, Int32(c)) {
                        cols.append(String(cString: cName))
                    } else {
                        cols.append("col_\(c)")
                    }
                }

                var rows: [[String?]] = []
                var stepRC = sqlite3_step(activeStmt)
                while stepRC == SQLITE_ROW {
                    var row: [String?] = []
                    row.reserveCapacity(colCount)
                    for c in 0..<colCount {
                        let colType = sqlite3_column_type(activeStmt, Int32(c))
                        if colType == SQLITE_NULL {
                            row.append(nil)
                        } else if let textPtr = sqlite3_column_text(activeStmt, Int32(c)) {
                            row.append(String(cString: textPtr))
                        } else {
                            row.append("")
                        }
                    }
                    rows.append(row)
                    stepRC = sqlite3_step(activeStmt)
                }

                if stepRC != SQLITE_DONE {
                    let err = String(cString: sqlite3_errmsg(db))
                    sqlite3_finalize(activeStmt)
                    stmt = nil
                    return err
                }

                if colCount > 0 {
                    lastColumns = cols
                    lastRows = rows
                } else {
                    totalAffected += Int(sqlite3_changes(db))
                }

                sqlite3_finalize(activeStmt)
                stmt = nil

                if let tail {
                    currentPtr = tail
                } else {
                    break
                }
            }
            return nil
        }

        let elapsedNs = DispatchTime.now().uptimeNanoseconds - startTime
        let elapsedMs = Double(elapsedNs) / 1_000_000.0

        return SQLQueryResult(
            sql: sql,
            columns: lastColumns,
            rows: lastRows,
            rowsAffected: totalAffected,
            executionTimeMs: elapsedMs,
            error: resultError
        )
    }

    // MARK: - Schema Introspection

    public func introspectSchema() -> SQLDatabaseSchema {
        let version = querySingleColumn("SELECT sqlite_version();").first ?? "3.x"
        let masterRes = execute("""
            SELECT type, name, tbl_name, COALESCE(sql, '')
            FROM sqlite_master
            WHERE name NOT LIKE 'sqlite_%'
            ORDER BY type, name;
            """)

        var tables: [SQLTableSchema] = []
        var views: [SQLTableSchema] = []
        var indexes: [SQLIndexInfo] = []
        var triggers: [SQLTriggerInfo] = []

        for row in masterRes.rows {
            guard row.count >= 4,
                  let type = row[0],
                  let name = row[1],
                  let tblName = row[2] else { continue }
            let ddl = row[3] ?? ""

            switch type {
            case "table":
                let cols = introspectColumns(of: name)
                let fks = introspectForeignKeys(of: name)
                let countStr = querySingleColumn("SELECT COUNT(*) FROM \"\(escapeIdent(name))\";").first ?? "0"
                let count = Int(countStr) ?? 0
                tables.append(SQLTableSchema(name: name, kind: "table", ddl: ddl, columns: cols, foreignKeys: fks, rowCount: count))
            case "view":
                let cols = introspectColumns(of: name)
                let countStr = querySingleColumn("SELECT COUNT(*) FROM \"\(escapeIdent(name))\";").first ?? "0"
                let count = Int(countStr) ?? 0
                views.append(SQLTableSchema(name: name, kind: "view", ddl: ddl, columns: cols, foreignKeys: [], rowCount: count))
            case "index":
                indexes.append(SQLIndexInfo(name: name, tableName: tblName, ddl: ddl))
            case "trigger":
                triggers.append(SQLTriggerInfo(name: name, tableName: tblName, ddl: ddl))
            default:
                break
            }
        }

        return SQLDatabaseSchema(
            databasePath: path,
            sqliteVersion: version,
            tables: tables,
            views: views,
            indexes: indexes,
            triggers: triggers
        )
    }

    private func introspectColumns(of relation: String) -> [SQLColumnInfo] {
        let res = execute("PRAGMA table_info(\"\(escapeIdent(relation))\");")
        return res.rows.compactMap { row -> SQLColumnInfo? in
            guard row.count >= 6,
                  let cidStr = row[0], let cid = Int(cidStr),
                  let name = row[1] else { return nil }
            let type = row[2] ?? "TEXT"
            let notNull = (row[3] == "1")
            let dflt = row[4]
            let pk = (Int(row[5] ?? "0") ?? 0) > 0
            return SQLColumnInfo(cid: cid, name: name, type: type, notNull: notNull, defaultValue: dflt, isPrimaryKey: pk)
        }
    }

    private func introspectForeignKeys(of table: String) -> [SQLForeignKeyInfo] {
        let res = execute("PRAGMA foreign_key_list(\"\(escapeIdent(table))\");")
        return res.rows.compactMap { row -> SQLForeignKeyInfo? in
            guard row.count >= 5,
                  let targetTable = row[2],
                  let fromCol = row[3],
                  let toCol = row[4] else { return nil }
            return SQLForeignKeyInfo(fromColumn: fromCol, targetTable: targetTable, targetColumn: toCol)
        }
    }

    private func querySingleColumn(_ sql: String) -> [String] {
        let res = execute(sql)
        return res.rows.compactMap { $0.first ?? nil }
    }

    public func escapeIdent(_ ident: String) -> String {
        ident.replacingOccurrences(of: "\"", with: "\"\"")
    }

    public func escapeLiteral(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    // MARK: - EXPLAIN QUERY PLAN Tree Builder

    public func explainQueryPlan(_ sql: String) -> [TreeNode] {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let res = execute("EXPLAIN QUERY PLAN \(trimmed)")
        guard res.isSuccess else {
            return [
                TreeNode(
                    id: "plan_err",
                    label: res.error ?? "Query error",
                    icon: "⚠",
                    iconColor: .brightRed
                )
            ]
        }

        var nodes: [TreeNode] = []
        for (idx, row) in res.rows.enumerated() {
            let detail = row.last??.trimmingCharacters(in: .whitespacesAndNewlines) ?? "STEP \(idx)"
            let icon: String
            let color: Color
            if detail.localizedCaseInsensitiveContains("USING INDEX") || detail.localizedCaseInsensitiveContains("PRIMARY KEY") {
                icon = "⚡"
                color = .brightGreen
            } else if detail.localizedCaseInsensitiveContains("SCAN") {
                icon = "🔍"
                color = .brightYellow
            } else {
                icon = "▸"
                color = .brightCyan
            }
            nodes.append(
                TreeNode(
                    id: "plan_\(idx)",
                    label: detail,
                    icon: icon,
                    iconColor: color,
                    isInitiallyExpanded: true
                )
            )
        }

        return [
            TreeNode(
                id: "plan_root",
                label: "Query Execution Plan (\(String(format: "%.2f", res.executionTimeMs)) ms)",
                icon: "🧭",
                iconColor: .brightCyan,
                isInitiallyExpanded: true,
                children: nodes
            )
        ]
    }

    // MARK: - Demo E-Commerce SQLite Seed (Customers, Products, Orders, Order Items, Views, Triggers)

    public func seedDemoSchemaAndData() {
        let seedSQL = """
        CREATE TABLE customers (
            customer_id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            tier TEXT NOT NULL DEFAULT 'STANDARD',
            country TEXT NOT NULL,
            created_at TEXT NOT NULL
        );

        CREATE TABLE products (
            product_id INTEGER PRIMARY KEY AUTOINCREMENT,
            sku TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            unit_price REAL NOT NULL,
            stock_qty INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE orders (
            order_id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id INTEGER NOT NULL REFERENCES customers(customer_id),
            status TEXT NOT NULL DEFAULT 'PAID',
            total_amount REAL NOT NULL,
            ordered_at TEXT NOT NULL
        );

        CREATE TABLE order_items (
            item_id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id INTEGER NOT NULL REFERENCES orders(order_id),
            product_id INTEGER NOT NULL REFERENCES products(product_id),
            quantity INTEGER NOT NULL,
            line_total REAL NOT NULL
        );

        CREATE TABLE audit_log (
            log_id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type TEXT NOT NULL,
            entity_name TEXT NOT NULL,
            details TEXT NOT NULL,
            logged_at TEXT NOT NULL
        );

        CREATE INDEX idx_orders_customer ON orders(customer_id);
        CREATE INDEX idx_orders_status ON orders(status);
        CREATE INDEX idx_products_category ON products(category);

        CREATE VIEW v_customer_revenue AS
        SELECT
            c.customer_id,
            c.name,
            c.tier,
            c.country,
            COUNT(o.order_id) AS order_count,
            COALESCE(ROUND(SUM(o.total_amount), 2), 0.0) AS lifetime_spend
        FROM customers c
        LEFT JOIN orders o ON o.customer_id = c.customer_id
        GROUP BY c.customer_id
        ORDER BY lifetime_spend DESC;

        CREATE TRIGGER trg_orders_insert_audit
        AFTER INSERT ON orders
        BEGIN
            INSERT INTO audit_log(event_type, entity_name, details, logged_at)
            VALUES ('ORDER_CREATED', 'orders', 'New order #' || NEW.order_id || ' amount=' || NEW.total_amount, NEW.ordered_at);
        END;

        INSERT INTO customers (name, email, tier, country, created_at) VALUES
            ('Ada Lovelace', 'ada@analytical.org', 'ENTERPRISE', 'UK', '2026-01-12'),
            ('Alan Turing', 'alan@bletchley.uk', 'ENTERPRISE', 'UK', '2026-02-04'),
            ('Grace Hopper', 'grace@navy.mil', 'PRO', 'USA', '2026-02-19'),
            ('Edsger Dijkstra', 'edsger@shortestpath.nl', 'PRO', 'Netherlands', '2026-03-08'),
            ('Margaret Hamilton', 'margaret@apollo.nasa.gov', 'ENTERPRISE', 'USA', '2026-03-25'),
            ('Ken Thompson', 'ken@bell-labs.org', 'STANDARD', 'USA', '2026-04-11'),
            ('Dennis Ritchie', 'dmr@bell-labs.org', 'PRO', 'USA', '2026-05-01'),
            ('Barbara Liskov', 'liskov@csail.mit.edu', 'ENTERPRISE', 'USA', '2026-06-15');

        INSERT INTO products (sku, title, category, unit_price, stock_qty) VALUES
            ('HW-M4MAX', 'Workstation M4 Max 128GB', 'Hardware', 3999.00, 18),
            ('HW-KB-MECH', 'Split Mechanical Keyboard', 'Peripherals', 249.50, 64),
            ('SW-DATAGRIP', 'SwiftGrip Pro License', 'Software', 199.00, 999),
            ('HW-MON-5K', 'UltraFine 5K Studio Display', 'Displays', 1499.00, 27),
            ('BK-DDIA', 'Designing Data-Intensive Apps', 'Books', 54.99, 140),
            ('HW-NVME-4T', 'PCIe Gen5 NVMe 4TB SSD', 'Storage', 389.00, 52);

        INSERT INTO orders (customer_id, status, total_amount, ordered_at) VALUES
            (1, 'SHIPPED', 4248.50, '2026-09-01 10:15'),
            (2, 'PAID', 1698.00, '2026-09-05 14:22'),
            (3, 'SHIPPED', 598.00, '2026-09-12 09:05'),
            (1, 'DELIVERED', 1499.00, '2026-09-18 16:40'),
            (5, 'PAID', 4388.00, '2026-10-02 11:30'),
            (4, 'PENDING', 253.99, '2026-10-14 08:50'),
            (8, 'SHIPPED', 1888.00, '2026-10-21 19:12');

        INSERT INTO order_items (order_id, product_id, quantity, line_total) VALUES
            (1, 1, 1, 3999.00),
            (1, 2, 1, 249.50),
            (2, 4, 1, 1499.00),
            (2, 3, 1, 199.00),
            (3, 3, 3, 597.00),
            (4, 4, 1, 1499.00),
            (5, 1, 1, 3999.00),
            (5, 6, 1, 389.00),
            (6, 3, 1, 199.00),
            (6, 5, 1, 54.99),
            (7, 4, 1, 1499.00),
            (7, 6, 1, 389.00);
        """
        _ = execute(seedSQL)
    }
}
