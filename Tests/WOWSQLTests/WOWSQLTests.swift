//
//  WOWSQLTests.swift
//  WOWSQLTests
//
//  Created by WOWSQL Team
//  Copyright © 2024 WOWSQL. All rights reserved.
//

import XCTest
@testable import WOWSQL

final class WOWSQLTests: XCTestCase {
    
    func testClientInitialization() {
        let client = WOWSQLClient(
            projectUrl: "https://test.wowsql.com",
            apiKey: "test-api-key"
        )
        
        XCTAssertNotNil(client)
        XCTAssertEqual(client.baseUrl, "https://test.wowsql.com")
    }
    
    func testClientInitializationWithTrailingSlash() {
        let client = WOWSQLClient(
            projectUrl: "https://test.wowsql.com/",
            apiKey: "test-api-key"
        )
        
        XCTAssertEqual(client.baseUrl, "https://test.wowsql.com")
    }
    
    func testStorageClientInitialization() {
        let storage = WOWSQLStorage(
            projectUrl: "https://test.wowsql.com",
            apiKey: "test-api-key"
        )
        
        XCTAssertNotNil(storage)
    }
    
    func testTableCreation() {
        let client = WOWSQLClient(
            projectUrl: "https://test.wowsql.com",
            apiKey: "test-api-key"
        )
        
        let table = client.table("users")
        XCTAssertNotNil(table)
    }
}

