import Foundation
import Testing
@testable import SquareOff

struct DeepLinkTests {
    private func parse(_ string: String) -> DeepLink? { DeepLink.parse(URL(string: string)!) }

    @Test func inviteLinks() {
        #expect(parse("squareoff://join/42424") == .join(code: 42424))
        #expect(parse("https://square-off.com/guest/42424") == .join(code: 42424))
        #expect(parse("https://localhost:5173/guest/7") == .join(code: 7))
        #expect(parse("https://square-off.com/guest/abc") == nil)
        #expect(parse("squareoff://join/") == nil)
    }

    @Test func passwordResetLinks() {
        #expect(parse("squareoff://reset-password?token=abc-123") == .passwordReset(token: "abc-123"))
        #expect(parse("https://square-off.com/reset-password?token=abc-123") == .passwordReset(token: "abc-123"))
        #expect(parse("https://square-off.com/reset-password/abc-123") == .passwordReset(token: "abc-123"))
        #expect(parse("https://square-off.com/reset-password") == nil)
        #expect(parse("https://square-off.com/reset-password?token=") == nil)
    }

    @Test func authCallbackAndStrangers() {
        #expect(parse("squareoff://auth?token=x") == .authCallback(URL(string: "squareoff://auth?token=x")!))
        #expect(parse("squareoff://nope/1") == nil)
        #expect(parse("https://square-off.com/instructions") == nil)
        #expect(parse("mailto:someone@example.com") == nil)
    }
}
