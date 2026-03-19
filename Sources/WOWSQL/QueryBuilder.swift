//
//  QueryBuilder.swift
//  WOWSQL
//
//  Created by WOWSQL Team
//  Copyright © 2024 WOWSQL. All rights reserved.
//

import Foundation

/// Paginated response wrapper
public struct PaginatedResponse {
    public let data: [[String: Any]]
    public let page: Int
    public let perPage: Int
    public let total: Int
    public let totalPages: Int
}

/// Fluent query builder for constructing and executing queries
public class QueryBuilder {
    private let client: WOWSQLClient
    private let tableName: String
    private var selectedColumns: [String]?
    private var filters: [FilterExpression] = []
    private var groupByColumns: [String]?
    private var havingFilters: [HavingFilter] = []
    private var orderColumn: String?
    private var orderItems: [OrderByItem]?
    private var orderDirection: SortDirection?
    private var limitValue: Int?
    private var offsetValue: Int?
    
    internal init(client: WOWSQLClient, tableName: String) {
        self.client = client
        self.tableName = tableName
    }
    
    // MARK: - Select
    
    @discardableResult
    public func select(_ columns: [String]) -> QueryBuilder {
        selectedColumns = columns
        return self
    }
    
    // MARK: - Filters
    
    @discardableResult
    public func filter(_ column: String, _ op: FilterOperator, _ value: AnyCodable, _ logicalOp: String = "AND") -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: op, value: value, logicalOp: logicalOp))
        return self
    }
    
    @discardableResult
    public func eq(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .eq, value: value, logicalOp: "AND"))
        return self
    }
    
    @discardableResult
    public func neq(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .neq, value: value, logicalOp: "AND"))
        return self
    }

    @discardableResult
    public func gt(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .gt, value: value, logicalOp: "AND"))
        return self
    }

    @discardableResult
    public func gte(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .gte, value: value, logicalOp: "AND"))
        return self
    }

    @discardableResult
    public func lt(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .lt, value: value, logicalOp: "AND"))
        return self
    }

    @discardableResult
    public func lte(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .lte, value: value, logicalOp: "AND"))
        return self
    }

    @discardableResult
    public func like(_ column: String, _ pattern: String) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .like, value: AnyCodable(pattern), logicalOp: "AND"))
        return self
    }

    @discardableResult
    public func isNull(_ column: String) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .isNull, value: nil, logicalOp: "AND"))
        return self
    }

    @discardableResult
    public func isNotNull(_ column: String) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .isNot, value: nil, logicalOp: "AND"))
        return self
    }

    @discardableResult
    public func inList(_ column: String, _ values: [AnyCodable]) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .in, value: AnyCodable(values), logicalOp: "AND"))
        return self
    }

    @discardableResult
    public func notIn(_ column: String, _ values: [AnyCodable]) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .notIn, value: AnyCodable(values), logicalOp: "AND"))
        return self
    }

    @discardableResult
    public func between(_ column: String, _ min: AnyCodable, _ max: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .between, value: AnyCodable([min, max]), logicalOp: "AND"))
        return self
    }

    @discardableResult
    public func notBetween(_ column: String, _ min: AnyCodable, _ max: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .notBetween, value: AnyCodable([min, max]), logicalOp: "AND"))
        return self
    }

    @discardableResult
    public func orFilter(_ column: String, _ op: FilterOperator, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: op, value: value, logicalOp: "OR"))
        return self
    }

    // MARK: - Grouping / Having

    @discardableResult
    public func groupBy(_ columns: [String]) -> QueryBuilder {
        groupByColumns = columns
        return self
    }

    @discardableResult
    public func groupBy(_ column: String) -> QueryBuilder {
        groupByColumns = [column]
        return self
    }

    @discardableResult
    public func having(_ column: String, _ op: String, _ value: AnyCodable) -> QueryBuilder {
        havingFilters.append(HavingFilter(column: column, operator: op, value: value))
        return self
    }

    // MARK: - Ordering

    @discardableResult
    public func orderBy(_ column: String, _ direction: SortDirection = .asc) -> QueryBuilder {
        orderColumn = column
        orderDirection = direction
        return self
    }
    
    @discardableResult
    public func order(_ column: String, _ direction: SortDirection = .asc) -> QueryBuilder {
        return orderBy(column, direction)
    }

    @discardableResult
    public func orderByMultiple(_ items: [OrderByItem]) -> QueryBuilder {
        orderItems = items
        return self
    }
    
    // MARK: - Pagination
    
    @discardableResult
    public func limit(_ value: Int) -> QueryBuilder {
        limitValue = value
        return self
    }
    
    @discardableResult
    public func offset(_ value: Int) -> QueryBuilder {
        offsetValue = value
        return self
    }
    
    // MARK: - Execution
    
    /// Execute query and return typed results.
    public func execute<T: Codable>() async throws -> QueryResponse<T> {
        let hasAdvancedFeatures = 
            (groupByColumns != nil && !groupByColumns!.isEmpty) ||
            !havingFilters.isEmpty ||
            (orderItems != nil && !orderItems!.isEmpty) ||
            filters.contains { f in
                f.operator == .in || f.operator == .notIn || 
                f.operator == .between || f.operator == .notBetween
            }
        
        let response: [String: AnyCodable]
        
        if hasAdvancedFeatures {
            let body = buildQueryBody()
            let url = URL(string: "\(client.apiUrl)/\(tableName)/query")!
            response = try await client.executeRequest(url: url, method: "POST", body: body)
        } else {
            let url = URL(string: "\(client.apiUrl)/\(tableName)")!
            let params = buildQueryParams()
            var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
            let finalUrl = urlComponents.url!
            response = try await client.executeRequest(url: finalUrl, method: "GET", body: nil)
        }
        
        if let dataArray = response["data"]?.value as? [[String: Any]] {
            let jsonData = try JSONSerialization.data(withJSONObject: dataArray)
            let data = try JSONDecoder().decode([T].self, from: jsonData)
            let count = response["count"]?.value as? Int ?? data.count
            let total = response["total"]?.value as? Int
            let error = response["error"]?.value as? String
            return QueryResponse(data: data, count: count, total: total, error: error)
        }
        
        return QueryResponse(data: [], count: 0)
    }

    /// Get query results (alias for execute).
    public func get<T: Codable>() async throws -> QueryResponse<T> {
        return try await execute()
    }
    
    /// Get first result.
    public func first<T: Codable>() async throws -> T? {
        return try await limit(1).execute().data.first
    }
    
    /// Get exactly one record. Throws if zero or more than one found.
    public func single<T: Codable>() async throws -> T {
        let result: QueryResponse<T> = try await limit(2).execute()
        if result.data.isEmpty {
            throw WOWSQLError("No records found")
        }
        if result.data.count > 1 {
            throw WOWSQLError("Multiple records found, expected exactly one")
        }
        return result.data[0]
    }
    
    /// Get the total count of records matching the current filters.
    public func count() async throws -> Int {
        let savedSelect = selectedColumns
        let savedGroup = groupByColumns
        let savedHaving = havingFilters
        let savedOrder = orderColumn
        let savedDir = orderDirection
        
        selectedColumns = ["COUNT(*) as count"]
        groupByColumns = nil
        havingFilters = []
        orderColumn = nil
        orderDirection = nil
        
        defer {
            selectedColumns = savedSelect
            groupByColumns = savedGroup
            havingFilters = savedHaving
            orderColumn = savedOrder
            orderDirection = savedDir
        }
        
        let result: QueryResponse<[String: AnyCodable]> = try await execute()
        if let first = result.data.first, let countVal = first["count"]?.value {
            if let intVal = countVal as? Int { return intVal }
            if let strVal = countVal as? String, let intVal = Int(strVal) { return intVal }
        }
        return 0
    }
    
    /// Paginate results with page-based interface.
    public func paginate(page: Int = 1, perPage: Int = 20) async throws -> PaginatedResponse {
        let offsetVal = (max(page, 1) - 1) * perPage
        let result: QueryResponse<[String: AnyCodable]> = try await limit(perPage).offset(offsetVal).execute()
        let total = result.total ?? result.count
        let totalPages = total > 0 ? (total + perPage - 1) / perPage : 0
        
        let rawData: [[String: Any]] = result.data.map { dict in
            dict.mapValues { $0.value }
        }
        
        return PaginatedResponse(
            data: rawData,
            page: page,
            perPage: perPage,
            total: total,
            totalPages: totalPages
        )
    }
    
    // MARK: - Mutation Methods on QueryBuilder
    
    public func insert(_ data: [String: AnyCodable]) async throws -> CreateResponse {
        return try await create(data)
    }
    
    public func create(_ data: [String: AnyCodable]) async throws -> CreateResponse {
        let url = URL(string: "\(client.apiUrl)/\(tableName)")!
        return try await client.executeRequest(url: url, method: "POST", body: data)
    }
    
    public func update(_ data: [String: AnyCodable]) async throws -> UpdateResponse {
        var body: [String: AnyCodable] = ["data": AnyCodable(data)]
        if !filters.isEmpty {
            let filterArray = filters.map { filter -> [String: AnyCodable] in
                [
                    "column": AnyCodable(filter.column),
                    "operator": AnyCodable(filter.`operator`.rawValue),
                    "value": filter.value ?? AnyCodable(NSNull())
                ]
            }
            body["filters"] = AnyCodable(filterArray)
        }
        
        let url = URL(string: "\(client.apiUrl)/\(tableName)")!
        return try await client.executeRequest(url: url, method: "PATCH", body: body)
    }
    
    public func delete() async throws -> DeleteResponse {
        var body: [String: AnyCodable] = [:]
        if !filters.isEmpty {
            let filterArray = filters.map { filter -> [String: AnyCodable] in
                [
                    "column": AnyCodable(filter.column),
                    "operator": AnyCodable(filter.`operator`.rawValue),
                    "value": filter.value ?? AnyCodable(NSNull())
                ]
            }
            body["filters"] = AnyCodable(filterArray)
        }
        
        let url = URL(string: "\(client.apiUrl)/\(tableName)")!
        return try await client.executeRequest(url: url, method: "DELETE", body: body)
    }
    
    // MARK: - Private Helpers
    
    private func buildQueryParams() -> [String: AnyCodable] {
        var params: [String: AnyCodable] = [:]
        
        if let columns = selectedColumns {
            params["select"] = AnyCodable(columns.joined(separator: ","))
        }
        
        if !filters.isEmpty {
            let filterStrings = filters.map { filter -> String in
                let valueStr = filter.value?.value as? String ?? "\(filter.value?.value ?? "")"
                return "\(filter.column).\(filter.`operator`.rawValue).\(valueStr)"
            }
            params["filter"] = AnyCodable(filterStrings.joined(separator: ","))
        }
        
        if let orderCol = orderColumn {
            params["order"] = AnyCodable(orderCol)
        }
        
        if let orderDir = orderDirection {
            params["order_direction"] = AnyCodable(orderDir.rawValue)
        }
        
        if let limit = limitValue {
            params["limit"] = AnyCodable(limit)
        }
        
        if let offset = offsetValue {
            params["offset"] = AnyCodable(offset)
        }
        
        return params
    }
    
    private func buildQueryBody() -> [String: AnyCodable] {
        var body: [String: AnyCodable] = [:]
        
        if let columns = selectedColumns {
            body["select"] = AnyCodable(columns)
        }
        
        if !filters.isEmpty {
            let filterArray = filters.map { filter -> [String: AnyCodable] in
                var filterDict: [String: AnyCodable] = [
                    "column": AnyCodable(filter.column),
                    "operator": AnyCodable(filter.`operator`.rawValue),
                    "value": filter.value ?? AnyCodable(NSNull())
                ]
                if let logicalOp = filter.logicalOp {
                    filterDict["logical_op"] = AnyCodable(logicalOp)
                }
                return filterDict
            }
            body["filters"] = AnyCodable(filterArray)
        }
        
        if let groupBy = groupByColumns, !groupBy.isEmpty {
            body["group_by"] = AnyCodable(groupBy)
        }
        
        if !havingFilters.isEmpty {
            let havingArray = havingFilters.map { h -> [String: AnyCodable] in
                [
                    "column": AnyCodable(h.column),
                    "operator": AnyCodable(h.`operator`),
                    "value": h.value
                ]
            }
            body["having"] = AnyCodable(havingArray)
        }
        
        if let orderItems = orderItems, !orderItems.isEmpty {
            let orderArray = orderItems.map { item -> [String: AnyCodable] in
                [
                    "column": AnyCodable(item.column),
                    "direction": AnyCodable(item.direction.rawValue)
                ]
            }
            body["order_by"] = AnyCodable(orderArray)
        } else if let orderCol = orderColumn {
            body["order_by"] = AnyCodable(orderCol)
            if let orderDir = orderDirection {
                body["order_direction"] = AnyCodable(orderDir.rawValue)
            }
        }
        
        if let limit = limitValue {
            body["limit"] = AnyCodable(limit)
        }
        
        if let offset = offsetValue {
            body["offset"] = AnyCodable(offset)
        }
        
        return body
    }
}
