import XCTest
import Vapor
import HTTP
@testable import VaporAuth

class TokenTests: XCTestCase {
    static var allTests = [
        ("testAuthentication", testAuthentication),
        ("testPersistance", testPersistance)
    ]
}

// MARK: Stateless

import Authentication
import Fluent

// Tests stateless token authentication
//
// `Authorization: Bearer <token here>` header must be passed
// with every request

struct Token: TokenProtocol {
    // This would be automatically implemented
    // if the Token where an Entity

    static func findUser<U : Entity>(for token: Authentication.Token) throws -> U {
        // initializer a user with a name
        // being the token's name
        let node = try Node(node: [
            "name": token.string
        ])

        return try U.init(node: node)
    }
}

extension TestUser: TokenAuthenticatable {
    // This is the only conformance needed to make
    // TestUser authenticatable with tokens!
    public typealias TokenType = Token
}

extension TokenTests {
    // Test stateless token authentication
    func testAuthentication() throws {
        let drop = Droplet()

        drop.middleware += TokenAuthenticationMiddleware(TestUser.self)

        drop.get("name") { req in
            // return the users name
            return try req.auth.user(TestUser.self).name
        }

        let token = "foo"

        let req = try Request(.get, "name")
        req.headers["Authorization"] = "Bearer \(token)"
        let res = try drop.respond(to: req)

        XCTAssertEqual(res.body.bytes?.string, token)
    }
}

// MARK: Sessions

// Session based token authentication
//
// `Authorization: Bearer <token here>` header must only be passed once
// After that, the cookie can act as a login persister

import Sessions

extension TestUser: SessionPersistable {
    public static func fetchPersisted(for req: Request) throws -> Self? {
        // take the cookie and set it as the user's
        // name for easy verification
        guard let cookie = req.cookies["vapor-sessions"] else {
            return nil
        }
        return self.init(name: cookie)
    }
}

extension TokenTests {

    func testPersistance() throws {
        let drop = Droplet()

        let sessions = MemorySessions()
        drop.middleware += SessionsMiddleware(sessions: sessions)
        drop.middleware += PersistMiddleware(TestUser.self)
        drop.middleware += TokenLoginMiddleware(TestUser.self)

        // add the token middleware to a route group
        drop.get("name") { req in
            // return the users name
            return try req.auth.user(TestUser.self).name
        }

        let token = "foo"

        // login request with token
        let req = try Request(.get, "name")
        req.headers["Authorization"] = "Bearer \(token)"
        let res = try drop.respond(to: req)

        // verify response and get cookie
        XCTAssertEqual(res.body.bytes?.string, token)
        guard let cookie = res.cookies["vapor-sessions"] else {
            XCTFail("No cookie")
            return
        }

        // logged in request with cookie
        let req2 = try Request(.get, "name")
        req2.cookies["vapor-sessions"] = cookie
        let res2 = try drop.respond(to: req2)

        XCTAssertEqual(res2.body.bytes?.string, cookie)
    }
}

