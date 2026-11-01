import Foundation
import SwiftTUI

// MARK: - SQL Syntax Highlighter

public enum SQLSyntaxHighlighter {
    public static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS",
        "ON", "AS", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "DISTINCT",
        "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE",
        "VIEW", "INDEX", "TRIGGER", "DROP", "ALTER", "PRIMARY", "KEY", "FOREIGN",
        "REFERENCES", "UNIQUE", "NOT", "NULL", "DEFAULT", "AUTOINCREMENT", "AND",
        "OR", "IN", "IS", "BETWEEN", "LIKE", "GLOB", "CASE", "WHEN", "THEN", "ELSE",
        "END", "ASC", "DESC", "UNION", "ALL", "EXISTS", "WITH", "RECURSIVE", "PRAGMA",
        "EXPLAIN", "QUERY", "PLAN", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION",
        "AFTER", "BEFORE", "EACH", "ROW"
    ]

    public static let functions: Set<String> = [
        "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "IFNULL", "NULLIF",
        "ROUND", "ABS", "UPPER", "LOWER", "LENGTH", "SUBSTR", "TRIM", "REPLACE",
        "STRFTIME", "DATE", "DATETIME", "TIME", "JULIANDAY", "GROUP_CONCAT",
        "TOTAL", "TYPEOF", "RANDOM", "HEX", "JSON_EXTRACT"
    ]

    public static let types: Set<String> = [
        "INTEGER", "INT", "REAL", "FLOAT", "DOUBLE", "TEXT", "VARCHAR", "BLOB", "BOOLEAN", "NUMERIC"
    ]

    public static func highlightLine(_ line: String, schemaRelationNames: Set<String> = []) -> [StyledSpan] {
        guard !line.isEmpty else { return [] }
        let chars = Array(line)
        var spans: [StyledSpan] = []
        var i = 0
        let n = chars.count

        while i < n {
            let c = chars[i]

            // 1. Line comment `-- ...`
            if c == "-" && i + 1 < n && chars[i + 1] == "-" {
                let comment = String(chars[i..<n])
                spans.append(StyledSpan(comment, style: CellStyle(fg: .brightBlack, modifiers: [.italic])))
                break
            }

            // 2. Single-quoted string literal `'...'`
            if c == "'" {
                var end = i + 1
                while end < n {
                    if chars[end] == "'" {
                        if end + 1 < n && chars[end + 1] == "'" {
                            end += 2
                            continue
                        }
                        end += 1
                        break
                    }
                    end += 1
                }
                let literal = String(chars[i..<end])
                spans.append(StyledSpan(literal, style: CellStyle(fg: .brightGreen)))
                i = end
                continue
            }

            // 3. Numeric literal
            if c.isNumber {
                var end = i + 1
                while end < n && (chars[end].isNumber || chars[end] == ".") {
                    end += 1
                }
                let numStr = String(chars[i..<end])
                spans.append(StyledSpan(numStr, style: CellStyle(fg: .brightCyan)))
                i = end
                continue
            }

            // 4. Identifier or Keyword
            if c.isLetter || c == "_" {
                var end = i + 1
                while end < n && (chars[end].isLetter || chars[end].isNumber || chars[end] == "_") {
                    end += 1
                }
                let word = String(chars[i..<end])
                let upper = word.uppercased()
                let lower = word.lowercased()

                if keywords.contains(upper) {
                    spans.append(StyledSpan(word, style: CellStyle(fg: .orange, modifiers: [.bold])))
                } else if functions.contains(upper) {
                    spans.append(StyledSpan(word, style: CellStyle(fg: .brightBlue, modifiers: [.bold])))
                } else if types.contains(upper) {
                    spans.append(StyledSpan(word, style: CellStyle(fg: .brightMagenta)))
                } else if schemaRelationNames.contains(lower) {
                    spans.append(StyledSpan(word, style: CellStyle(fg: .brightYellow, modifiers: [.bold])))
                } else {
                    spans.append(StyledSpan(word, style: CellStyle(fg: .white)))
                }
                i = end
                continue
            }

            // 5. Punctuation / Operators / Whitespace
            var end = i + 1
            while end < n && !chars[end].isLetter && !chars[end].isNumber && chars[end] != "_" && chars[end] != "'" && chars[end] != "-" {
                end += 1
            }
            let punct = String(chars[i..<end])
            spans.append(StyledSpan(punct, style: CellStyle(fg: .brightWhite)))
            i = end
        }

        return spans
    }
}

// MARK: - Schema-Aware SQL Autocomplete Engine

public struct SQLAutocompleteEngine {
    public init() {}

    /// Computes ranked SQL completions for the SQL Console or Table Filter bar.
    public static func completions(
        for context: AutocompleteContext,
        schema: SQLDatabaseSchema,
        defaultTable: String? = nil
    ) -> [AutocompleteItem] {
        let query = context.prefix

        // 1. If dot-qualified (`alias.col` or `table.col`), resolve the qualifier to a table/view!
        if let qualifier = context.qualifier, !qualifier.isEmpty {
            let aliasMap = parseTableAliases(from: context.fullText, schema: schema)
            let targetRelationName = aliasMap[qualifier.lowercased()] ?? qualifier
            if let rel = schema.relation(named: targetRelationName) {
                return rankAndFilter(
                    candidates: rel.columns.map { col in
                        AutocompleteItem(
                            id: "col:\(rel.name).\(col.name)",
                            label: col.name,
                            insertText: col.name,
                            kind: .column,
                            detail: "\(rel.name) • \(col.summaryBadge)",
                            documentation: "Column \(col.name) (\(col.type)) in \(rel.kind) \(rel.name)",
                            sortPriority: col.isPrimaryKey ? 950 : 900
                        )
                    },
                    query: query
                )
            }
        }

        // 2. Inspect preceding SQL token to determine clause context (e.g. after FROM / JOIN / UPDATE / INTO)
        let precedingWord = extractPrecedingKeyword(in: context.lineText, beforeColumn: context.columnIndex - context.prefix.count)
        let isTableClause = ["FROM", "JOIN", "UPDATE", "INTO", "TABLE", "DESC", "PRAGMA"].contains(precedingWord)

        var candidates: [AutocompleteItem] = []

        // 3. Add Tables & Views
        let tablePriority = isTableClause ? 960 : 750
        for tbl in schema.tables {
            let colNames = tbl.columns.map(\.name).joined(separator: ", ")
            candidates.append(
                AutocompleteItem(
                    id: "tbl:\(tbl.name)",
                    label: tbl.name,
                    insertText: tbl.name,
                    kind: .table,
                    detail: "table (\(tbl.rowCount) rows)",
                    documentation: "Columns: \(colNames)",
                    sortPriority: tablePriority
                )
            )
        }
        for vw in schema.views {
            let colNames = vw.columns.map(\.name).joined(separator: ", ")
            candidates.append(
                AutocompleteItem(
                    id: "vw:\(vw.name)",
                    label: vw.name,
                    insertText: vw.name,
                    kind: .view,
                    detail: "view (\(vw.rowCount) rows)",
                    documentation: "View columns: \(colNames)",
                    sortPriority: tablePriority - 10
                )
            )
        }

        // If right after FROM or JOIN, primarily show tables & views unless prefix matches something else
        if isTableClause {
            return rankAndFilter(candidates: candidates, query: query)
        }

        // 4. Add Columns (prioritizing `defaultTable` or tables referenced in `context.fullText`)
        let referencedRelations = findReferencedRelations(in: context.fullText, schema: schema, defaultTable: defaultTable)
        let relationsForColumns = referencedRelations.isEmpty ? schema.allRelations : referencedRelations

        var seenColumns: Set<String> = []
        for rel in relationsForColumns {
            let isPrimaryRel = (rel.name.lowercased() == defaultTable?.lowercased()) || !referencedRelations.isEmpty
            let baseColPriority = isPrimaryRel ? 880 : 700
            for col in rel.columns {
                let dedupKey = col.name.lowercased()
                if seenColumns.contains(dedupKey) && defaultTable != nil {
                    continue
                }
                seenColumns.insert(dedupKey)
                candidates.append(
                    AutocompleteItem(
                        id: "col:\(rel.name).\(col.name)",
                        label: col.name,
                        insertText: col.name,
                        kind: .column,
                        detail: "\(rel.name) • \(col.summaryBadge)",
                        documentation: "Column \(col.name) (\(col.type)) of \(rel.name)",
                        sortPriority: baseColPriority + (col.isPrimaryKey ? 15 : 0)
                    )
                )
            }
        }

        // 5. Add Built-in SQL Functions
        let functionDocs: [(name: String, insert: String, sig: String, doc: String)] = [
            ("COUNT", "COUNT(*)", "Aggregate", "Returns the number of rows matching the query criteria."),
            ("SUM", "SUM()", "Aggregate", "Calculates the sum of all non-NULL values in a group."),
            ("AVG", "AVG()", "Aggregate", "Calculates the average value of all non-NULL values."),
            ("MIN", "MIN()", "Aggregate", "Returns the minimum value in a group."),
            ("MAX", "MAX()", "Aggregate", "Returns the maximum value in a group."),
            ("COALESCE", "COALESCE()", "Null-safe", "Returns the first non-NULL argument."),
            ("ROUND", "ROUND()", "Numeric", "Rounds a floating-point value to N decimal digits."),
            ("UPPER", "UPPER()", "String", "Converts a string to uppercase."),
            ("LOWER", "LOWER()", "String", "Converts a string to lowercase."),
            ("LENGTH", "LENGTH()", "String", "Returns the character length of a string."),
            ("STRFTIME", "strftime('%Y-%m-%d', )", "Date/Time", "Formats a date/time string according to a format specifier."),
            ("GROUP_CONCAT", "GROUP_CONCAT()", "Aggregate", "Concatenates non-NULL values from a group into a string.")
        ]
        for fn in functionDocs {
            candidates.append(
                AutocompleteItem(
                    id: "fn:\(fn.name)",
                    label: "\(fn.name)()",
                    insertText: fn.insert,
                    kind: .function,
                    detail: fn.sig,
                    documentation: fn.doc,
                    sortPriority: 680
                )
            )
        }

        // 6. Add SQL Keywords & Clause Snippets
        let coreKeywords: [(kw: String, insert: String, detail: String)] = [
            ("SELECT", "SELECT ", "SQL clause"),
            ("FROM", "FROM ", "SQL clause"),
            ("WHERE", "WHERE ", "SQL clause"),
            ("LEFT JOIN", "LEFT JOIN ", "SQL join"),
            ("INNER JOIN", "INNER JOIN ", "SQL join"),
            ("GROUP BY", "GROUP BY ", "SQL clause"),
            ("ORDER BY", "ORDER BY ", "SQL clause"),
            ("HAVING", "HAVING ", "SQL clause"),
            ("LIMIT", "LIMIT ", "SQL clause"),
            ("OFFSET", "OFFSET ", "SQL clause"),
            ("INSERT INTO", "INSERT INTO ", "SQL DML"),
            ("UPDATE", "UPDATE ", "SQL DML"),
            ("DELETE FROM", "DELETE FROM ", "SQL DML"),
            ("VALUES", "VALUES ", "SQL DML"),
            ("DISTINCT", "DISTINCT ", "SQL modifier"),
            ("AND", "AND ", "Logical operator"),
            ("OR", "OR ", "Logical operator"),
            ("NOT NULL", "NOT NULL", "Constraint/Predicate"),
            ("IS NULL", "IS NULL", "Predicate"),
            ("IS NOT NULL", "IS NOT NULL", "Predicate"),
            ("LIKE", "LIKE '%'", "Pattern match"),
            ("BETWEEN", "BETWEEN ", "Range predicate"),
            ("IN", "IN ()", "Set predicate"),
            ("ASC", "ASC", "Sort ascending"),
            ("DESC", "DESC", "Sort descending"),
            ("EXPLAIN QUERY PLAN", "EXPLAIN QUERY PLAN ", "SQLite diagnostic")
        ]
        for item in coreKeywords {
            candidates.append(
                AutocompleteItem(
                    id: "kw:\(item.kw)",
                    label: item.kw,
                    insertText: item.insert,
                    kind: .keyword,
                    detail: item.detail,
                    documentation: "SQLite keyword: \(item.kw)",
                    sortPriority: 620
                )
            )
        }

        return rankAndFilter(candidates: candidates, query: query)
    }

    // MARK: - Helpers

    private static func rankAndFilter(candidates: [AutocompleteItem], query: String) -> [AutocompleteItem] {
        var scored: [(item: AutocompleteItem, score: Int)] = []
        for item in candidates {
            if let match = AutocompleteContext.matchScore(candidate: item.label, query: query) {
                // Avoid suggesting a word that is already 100% identical to what's typed unless explicitly triggered
                if !query.isEmpty && item.label.lowercased() == query.lowercased() && item.insertText.trimmingCharacters(in: .whitespaces) == query {
                    continue
                }
                scored.append((item, match + item.sortPriority))
            }
        }
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.item.label < b.item.label
        }
        return Array(scored.prefix(25).map(\.item))
    }

    private static func extractPrecedingKeyword(in line: String, beforeColumn col: Int) -> String {
        let chars = Array(line)
        var idx = max(0, min(chars.count, col))
        while idx > 0 && chars[idx - 1].isWhitespace {
            idx -= 1
        }
        let end = idx
        while idx > 0 && (chars[idx - 1].isLetter || chars[idx - 1] == "_") {
            idx -= 1
        }
        guard idx < end else { return "" }
        return String(chars[idx..<end]).uppercased()
    }

    /// Parses `FROM <table> [AS] <alias>` and `JOIN <table> [AS] <alias>` in the SQL text.
    public static func parseTableAliases(from sql: String, schema: SQLDatabaseSchema) -> [String: String] {
        var map: [String: String] = [:]
        for rel in schema.allRelations {
            map[rel.name.lowercased()] = rel.name
        }

        let tokens = sql
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        var i = 0
        while i < tokens.count {
            let upper = tokens[i].uppercased()
            if (upper == "FROM" || upper == "JOIN" || upper == "UPDATE") && i + 1 < tokens.count {
                let tableCandidate = tokens[i + 1].trimmingCharacters(in: CharacterSet(charactersIn: "\";()"))
                if let rel = schema.relation(named: tableCandidate) {
                    if i + 2 < tokens.count {
                        let nextToken = tokens[i + 2]
                        if nextToken.uppercased() == "AS", i + 3 < tokens.count {
                            let alias = tokens[i + 3].trimmingCharacters(in: CharacterSet(charactersIn: "\";(),"))
                            map[alias.lowercased()] = rel.name
                        } else if !SQLSyntaxHighlighter.keywords.contains(nextToken.uppercased()) {
                            let alias = nextToken.trimmingCharacters(in: CharacterSet(charactersIn: "\";(),"))
                            if !alias.isEmpty {
                                map[alias.lowercased()] = rel.name
                            }
                        }
                    }
                }
            }
            i += 1
        }
        return map
    }

    private static func findReferencedRelations(
        in sql: String,
        schema: SQLDatabaseSchema,
        defaultTable: String?
    ) -> [SQLTableSchema] {
        var found: [SQLTableSchema] = []
        if let defaultTable, let rel = schema.relation(named: defaultTable) {
            found.append(rel)
        }
        let lowerSQL = sql.lowercased()
        for rel in schema.allRelations {
            if lowerSQL.contains(rel.name.lowercased()) && !found.contains(rel) {
                found.append(rel)
            }
        }
        return found
    }
}
