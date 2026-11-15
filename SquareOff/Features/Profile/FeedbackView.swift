import SquareOffNet
import SwiftUI

/// What the feedback form collects (web `feedback-modal.tsx`), validated like the server's
/// `FeedbackSchema`, with the app version and device appended once so support knows what ran.
nonisolated struct FeedbackDraft: Equatable {
    var subject = ""
    var message = ""
    var displayName = ""
    var contactEmail = ""

    static func isValidEmail(_ value: String) -> Bool {
        value.wholeMatch(of: /^[^\s@]+@[^\s@]+\.[^\s@]+$/) != nil
    }

    func validate() -> [String: String] {
        var errors: [String: String] = [:]
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if subject.isEmpty { errors["subject"] = "Add a short subject" }
        else if subject.count > FeedbackRequest.subjectLimit { errors["subject"] = "Keep the subject under \(FeedbackRequest.subjectLimit) characters" }
        if message.isEmpty { errors["message"] = "Tell us what happened" }
        else if message.count > FeedbackRequest.messageLimit { errors["message"] = "That's a bit long: \(FeedbackRequest.messageLimit) characters max" }
        if displayName.trimmingCharacters(in: .whitespaces).count > FeedbackRequest.nameLimit { errors["displayName"] = "Keep the name under \(FeedbackRequest.nameLimit) characters" }
        let email = contactEmail.trimmingCharacters(in: .whitespaces)
        if !email.isEmpty, !Self.isValidEmail(email) { errors["contactEmail"] = "Enter a valid email address" }
        return errors
    }

    /// The request body: trimmed fields, empty optionals as nil, the context footer appended.
    func request(context: String? = nil, environment: String = FeedbackDraft.environmentLine()) -> FeedbackRequest {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let email = contactEmail.trimmingCharacters(in: .whitespaces)
        var body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var footer = "— \(environment)"
        if let context, !context.isEmpty { footer += ", \(context)" }
        if !body.hasSuffix(footer) { body += "\n\n" + footer }
        return FeedbackRequest(subject: subject.trimmingCharacters(in: .whitespacesAndNewlines), message: body,
                               contactEmail: email.isEmpty ? nil : email, displayName: name.isEmpty ? nil : name)
    }

    /// "Square Off iOS 1.0.0 (3), iOS 18.1, iPhone15,2".
    static func environmentLine(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Square Off iOS \(version) (\(build)), iOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(deviceModel())"
    }

    static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.isEmpty ? "unknown device" : machine
    }
}

/// Send feedback (web navbar `FeedbackModal`): subject, message, optional contact details
/// prefilled from the profile, `POST /feedback`. Opened from Profile and the game menu.
struct FeedbackView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// Where it was opened from ("8×8 vs CPU"), appended to the message for context.
    var context: String?

    @State private var draft = FeedbackDraft()
    @State private var errors: [String: String] = [:]
    @State private var failure: String?
    @State private var isBusy = false
    @State private var showsContact = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Tell us what works, what does not, and what you would like next. Your app version and device are included.")
                        .font(.subheadline).foregroundStyle(Theme.foregroundSecondary)
                    if let failure {
                        AlertBox(.danger, title: "Couldn't send feedback", message: failure)
                    }
                    LabeledField(label: "Subject", help: "A short headline helps us route your note.", error: errors["subject"]) {
                        TextField("What's this about?", text: $draft.subject)
                            .foregroundStyle(Theme.foreground)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Message").font(.subheadline.weight(.medium)).foregroundStyle(Theme.foreground)
                        TextEditor(text: $draft.message)
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(Theme.foreground)
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(errors["message"] == nil ? Theme.fieldBorder : Theme.danger))
                        if let error = errors["message"] {
                            Text(error).font(.caption).foregroundStyle(Theme.dangerText)
                        } else {
                            Text("Steps to reproduce and what you expected.").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    DisclosureGroup(isExpanded: $showsContact) {
                        VStack(spacing: 12) {
                            LabeledField(label: "Name", error: errors["displayName"]) {
                                TextField("Optional", text: $draft.displayName).foregroundStyle(Theme.foreground)
                            }
                            LabeledField(label: "Email", help: "Include your name and/or email only if you want us to get back to you.", error: errors["contactEmail"]) {
                                TextField("Optional", text: $draft.contactEmail)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .foregroundStyle(Theme.foreground)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Contact info (optional)").font(.subheadline.weight(.medium)).foregroundStyle(Theme.foreground)
                    }
                    .tint(Theme.link)
                    Button(action: send) {
                        PendingLabel(title: "Send message", pendingTitle: "Sending…", symbol: "paperplane", isPending: isBusy)
                    }
                    .buttonStyle(PrimaryButtonStyle(large: true))
                    .disabled(isBusy)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.overlay)
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isBusy)
                }
            }
        }
        .onAppear(perform: prefill)
    }

    private func prefill() {
        guard let profile = app.account.profile else { return }
        if draft.displayName.isEmpty {
            let name = [profile.firstName, profile.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            draft.displayName = name.isEmpty ? profile.username : name
        }
        if draft.contactEmail.isEmpty { draft.contactEmail = profile.email }
    }

    private func send() {
        errors = draft.validate()
        guard errors.isEmpty else {
            if errors["displayName"] != nil || errors["contactEmail"] != nil { showsContact = true }
            return
        }
        failure = nil
        isBusy = true
        let request = draft.request(context: context)
        Task {
            defer { isBusy = false }
            do {
                _ = try await app.backend.api.sendFeedback(request)
                dismiss()
                app.toasts.success("Thanks — your message was sent.",
                                   description: "We read every note. If you included contact info, we may follow up.")
            } catch {
                failure = Self.message(for: error)
            }
        }
    }

    static func message(for error: Error) -> String {
        if let api = error as? APIError {
            if api.status == 429 { return "You've sent a lot of feedback recently. Try again in an hour." }
            if let detail = api.detail, detail.count <= 160, !detail.contains("<"), !detail.contains("{") { return detail }
        }
        return "Could not send feedback. Please try again."
    }
}
