import Foundation
import SquareOffNet
import Testing
@testable import SquareOff

struct FeedbackTests {
    @Test func validationMirrorsTheServerSchema() {
        var draft = FeedbackDraft()
        #expect(Set(draft.validate().keys) == ["subject", "message"])
        draft.subject = String(repeating: "x", count: 201)
        draft.message = "Steps"
        #expect(draft.validate()["subject"]?.contains("200") == true)
        draft.subject = "Board"
        draft.contactEmail = "not-an-email"
        #expect(draft.validate().keys.contains("contactEmail"))
        draft.contactEmail = "   "
        draft.displayName = String(repeating: "n", count: 201)
        #expect(Set(draft.validate().keys) == ["displayName"])
        draft.displayName = "Pat"
        #expect(draft.validate().isEmpty)
    }

    @Test func requestTrimsAndAppendsTheEnvironmentOnce() {
        var draft = FeedbackDraft(subject: "  Board  ", message: "Tiles overlap\n", displayName: " ", contactEmail: " pat@example.com ")
        let request = draft.request(context: "8×8 vs CPU", environment: "Square Off iOS 1.0.0 (1), iOS 18.1, iPhone15,2")
        #expect(request.subject == "Board")
        #expect(request.message == "Tiles overlap\n\n— Square Off iOS 1.0.0 (1), iOS 18.1, iPhone15,2, 8×8 vs CPU")
        #expect(request.displayName == nil)
        #expect(request.contactEmail == "pat@example.com")
        // Sending the same draft again (a retry) does not stack footers.
        draft.message = request.message
        #expect(draft.request(context: "8×8 vs CPU", environment: "Square Off iOS 1.0.0 (1), iOS 18.1, iPhone15,2").message == request.message)
        #expect(FeedbackDraft.environmentLine().hasPrefix("Square Off iOS "))
    }

    @Test func serverErrorsBecomeShortCopy() {
        #expect(FeedbackView.message(for: APIError.http(status: 429, body: "{}")) == "You've sent a lot of feedback recently. Try again in an hour.")
        #expect(FeedbackView.message(for: APIError.http(status: 500, body: #"{"detail":"Could not send feedback. Please try again later."}"#)) == "Could not send feedback. Please try again later.")
        #expect(FeedbackView.message(for: APIError.http(status: 500, body: "<html>oops</html>")) == "Could not send feedback. Please try again.")
        #expect(FeedbackView.message(for: APIError.timeout) == "Could not send feedback. Please try again.")
    }

    @MainActor
    @Test func theSpyReceivesTheTrimmedRequest() async throws {
        let api = SpyAPI()
        let backend = Backend.test(api: api)
        let request = FeedbackDraft(subject: "Hi", message: "There").request(context: nil, environment: "env")
        _ = try await backend.api.sendFeedback(request)
        #expect(await api.feedbackRequests == [request])
    }
}
