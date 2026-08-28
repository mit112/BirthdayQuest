import SwiftUI

/// The point of agreement to the Terms of Use, shown on the two doors into an occasion —
/// creating one and joining one.
///
/// App Store Guideline 1.2 asks for more than reachable terms: users of an app carrying
/// user-generated content have to *agree* to them, and to a zero-tolerance policy in
/// particular. So the sentence names the act that constitutes agreement ("Creating an
/// occasion means…") and sits in the same form as the button that performs it, rather than
/// living only behind a settings row nobody opens.
///
/// It is a `NavigationLink` and not a modal so the terms can be read without abandoning a
/// half-filled form; both hosts push it onto a `NavigationStack` they already own.
struct TermsAgreementSection: View {

    /// The act being agreed to, as a capitalised gerund phrase — "Creating an occasion",
    /// "Joining an occasion". Interpolated as the sentence's subject.
    let act: String

    var body: some View {
        Section {
            NavigationLink {
                TermsView()
            } label: {
                Text("\(act) means you agree to the Terms of Use, including zero tolerance for objectionable content and abusive behaviour.")
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityHint("Opens the Terms of Use.")
        }
    }
}

#Preview {
    NavigationStack {
        Form {
            TermsAgreementSection(act: "Creating an occasion")
        }
    }
}
