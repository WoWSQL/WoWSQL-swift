//
//  QueryBuilder.swift
//  WOWSQL
//
//  Created by WOWSQL Team
//  Copyright © 2024 WOWSQL. All rights reserved.
//

import Foundation

/// Fluent query builder for constructing and executing queries
public class QueryBuilder {
    private let client: WOWSQLClient
    private let tableName: String
    private var selectedColumns: [String]?
    private var filters: [FilterExpression] = []
    private var groupBy: [String]?
    private var having: [HavingFilter] = []
    private var orderColumn: String?
    private var orderItems: [OrderByItem]?
    private var orderDirection: SortDirection?
    private var limitValue: Int?
    private var offsetValue: Int?
    
    internal init(client: WOWSQLClient, tableName: String) {
        self.client = client
        self.tableName = tableName
    }
    
    /// Select specific columns
    @discardableResult
    public func select(_ columns: [String]) -> QueryBuilder {
        selectedColumns = columns
        return self
    }
    
    /// Add a filter condition (generic method).
    @discardableResult
    public func filter(_ column: String, _ op: FilterOperator, _ value: AnyCodable, _ logicalOp: String = "AND") -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: op, value: value, logicalOp: logicalOp))
        return self
    }
    
    /// Add equality filter
    @discardableResult
    public func eq(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .eq, value: value, logicalOp: "AND"))
        return self
    }
    
    /// Add not-equal filter
    @discardableResult
    public func neq(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .neq, value: value, logicalOp: "AND"))
        return self
    }

    /// Add greater-than filter
    @discardableResult
    public func gt(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .gt, value: value, logicalOp: "AND"))
        return self
    }

    /// Add greater-than-or-equal filter
    @discardableResult
    public func gte(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .gte, value: value, logicalOp: "AND"))
        return self
    }

    /// Add less-than filter
    @discardableResult
    public func lt(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .lt, value: value, logicalOp: "AND"))
        return self
    }

    /// Add less-than-or-equal filter
    @discardableResult
    public func lte(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .lte, value: value, logicalOp: "AND"))
        return self
    }

    /// Add LIKE filter
    @discardableResult
    public func like(_ column: String, _ pattern: String) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .like, value: AnyCodable(pattern), logicalOp: "AND"))
        return self
    }

    /// Add IS NULL filter
    @discardableResult
    public func isNull(_ column: String) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .isNull, value: nil, logicalOp: "AND"))
        return self
    }

    /// Add IS NOT NULL filter
    @discardableResult
    public func isNotNull(_ column: String) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .isNot, value: nil, logicalOp: "AND"))
        return self
    }

    /// Add IN filter
    @discardableResult
    public func `in`(_ column: String, _ values: [AnyCodable]) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .in, value: AnyCodable(values), logicalOp: "AND"))
        return self
    }

    /// Add NOT IN filter
    @discardableResult
    public func notIn(_ column: String, _ values: [AnyCodable]) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .notIn, value: AnyCodable(values), logicalOp: "AND"))
        return self
    }

    /// Add BETWEEN filter
    @discardableResult
    public func between(_ column: String, _ min: AnyCodable, _ max: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .between, value: AnyCodable([min, max]), logicalOp: "AND"))
        return self
    }

    /// Add NOT BETWEEN filter
    @discardableResult
    public func notBetween(_ column: String, _ min: AnyCodable, _ max: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: .notBetween, value: AnyCodable([min, max]), logicalOp: "AND"))
        return self
    }

    /// Add filter with OR logical operator
    @discardableResult
    public func or(_ column: String, _ op: FilterOperator, _ value: AnyCodable) -> QueryBuilder {
        filters.append(FilterExpression(column: column, operator: op, value: value, logicalOp: "OR"))
        return self
    }

    /// Group results by column(s)
    @discardableResult
    public func groupBy(_ columns: [String]) -> QueryBuilder {
        groupBy = columns
        return self
    }

    /// Add HAVING clause filter
    @discardableResult
    public func having(_ column: String, _ op: String, _ value: AnyCodable) -> QueryBuilder {
        having.append(HavingFilter(column: column, operator: op, value: value))
        return self
    }

    /// Order by multiple columns
    @discardableResult
    public func orderByMultiple(_ items: [OrderByItem]) -> QueryBuilder {
        orderItems = items
        return self
    }
    
    /// Set order by
    @discardableResult
    public func orderBy(_ column: String, _ direction: SortDirection = .asc) -> QueryBuilder {
        orderColumn = column
        orderDirection = direction
        return self
    }
    
    /// Order results by column (alias for orderBy, backward compatibility).
    @discardableResult
    public func order(_ column: String, _ direction: SortDirection = .asc) -> QueryBuilder {
        return orderBy(column, direction)
    }
    
    /// Set limit
    @discardableResult
    public func limit(_ value: Int) -> QueryBuilder {
        limitValue = value
        return self
    }
    
    /// Set offset
    @discardableResult
    public func offset(_ value: Int) -> QueryBuilder {
        offsetValue = value
        return self
    }
    
    /// Execute query
    public func execute<T: Codable>() async throws -> QueryResponse<T> {
        // Check if we need POST endpoint (advanced features)
        let hasAdvancedFeatures = 
            (groupBy != nil && !groupBy!.isEmpty) ||
            !having.isEmpty ||
            (orderItems != nil && !orderItems!.isEmpty) ||
            filters.contains { f in
                f.operator == .in || f.operator == .notIn || 
                f.operator == .between || f.operator == .notBetween
            }
        
        let response: [String: AnyCodable]
        
        if hasAdvancedFeatures {
            // Use POST endpoint for advanced queries
            let body = buildQueryBody()
            let url = URL(string: "\(client.baseUrl)/api/v2/\(tableName)/query")!
            response = try await client.executeRequest(url: url, method: "POST", body: body)
        } else {
            // Use GET endpoint for simple queries (backward compatibility)
            let url = URL(string: "\(client.baseUrl)/api/v2/\(tableName)")!
            let params = buildQueryParams()
            var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
            let finalUrl = urlComponents.url!
            response = try await client.executeRequest(url: finalUrl, method: "GET", body: nil)
        }
        
        // Parse response
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

    /// Get query results (alias for execute)
    public func get<T: Codable>() async throws -> QueryResponse<T> {
        return try await execute()
    }
    
    /// Get first result
    public func first<T: Codable>() async throws -> T? {
        return try await limit(1).execute().data.first
    }
    
    /// Insert record (alias for create)
    public func insert(_ data: [String: AnyCodable]) async throws -> CreateResponse {
        return try await create(data)
    }
    
    /// Create record
    public func create(_ data: [String: AnyCodable]) async throws -> CreateResponse {
        let url = URL(string: "\(client.baseUrl)/api/v2/\(tableName)")!
        return try await client.executeRequest(url: url, method: "POST", body: data)
    }
    
    /// Update records
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
        
        let url = URL(string: "\(client.baseUrl)/api/v2/\(tableName)")!
        return try await client.executeRequest(url: url, method: "PATCH", body: body)
    }
    
    /// Delete records
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
        
        let url = URL(string: "\(client.baseUrl)/api/v2/\(tableName)")!
        return try await client.executeRequest(url: url, method: "DELETE", body: body)
    }
    
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
        
        if let groupBy = groupBy, !groupBy.isEmpty {
            body["group_by"] = AnyCodable(groupBy)
        }
        
        if !having.isEmpty {
            let havingArray = having.map { h -> [String: AnyCodable] in
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

