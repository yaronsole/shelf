import SwiftUI

/// In-app privacy policy, rendered as native text so it works offline and before
/// the hosted URL exists. Mirrors the hosted policy (privacy.html) — keep both in
/// sync if the policy changes. Reachable from Settings and the first-run consent.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Last updated: 19 June 2026")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Shelf is a book recommendation app for iPhone (\u{201C}the App\u{201D}). This policy explains what the App collects, why, and your choices. The App is operated by an individual developer (\u{201C}we\u{201D}, \u{201C}us\u{201D}). Contact: \(AppLinks.privacyEmail).")

                ForEach(Self.sections, id: \.heading) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.heading).font(.headline)
                        Text(section.body)
                            .font(.body)
                            .foregroundStyle(Color(.label))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
        }
        .navigationTitle(Strings.Settings.privacyRow)
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct Section { let heading: String; let body: String }

    private static let sections: [Section] = [
        Section(
            heading: "Who is responsible for your data",
            body: "Shelf is operated by an individual developer based in the United States, acting as the data controller for the limited data described below. We are not a company."
        ),
        Section(
            heading: "What we collect",
            body: "Shelf is designed to use as little personal data as possible. We do not ask you to create an account, and we do not ask for your name, email address, or contacts.\n\n•  Your book taste and reactions: books you add to your taste, save to your shelf, mark as read, like, or pass on. This is the core of how the App generates recommendations for you.\n•  An anonymous device identifier: when you first open the App, it generates a random, anonymous identifier stored on your device. This links your taste data to your device so your recommendations persist between sessions. It is not your name, email, phone number, or Apple ID, and it cannot be used to identify you personally.\n\nWe do not collect your precise location, contacts, photos, health data, financial information, or browsing activity in other apps."
        ),
        Section(
            heading: "How your data is used",
            body: "•  To generate personalized book recommendations.\n•  To remember the books you\u{2019}ve saved, read, or reacted to.\n•  To build an anonymous, aggregated \u{201C}Loved by readers\u{201D} list showing books that many users have enjoyed. This list only ever shows counts — never your name or identity, and never which specific books any individual liked. You can turn off your contribution to this list at any time in settings."
        ),
        Section(
            heading: "Artificial intelligence and third-party processing",
            body: "Shelf uses Anthropic\u{2019}s Claude AI service to generate recommendations. When you use the App, your book taste signals (the books you like and dislike) are sent to Anthropic\u{2019}s API to produce suggestions. No name, email, account, or personal identity is sent — only book preferences. Anthropic processes this data to return recommendations and under its own terms does not use API inputs to train its models. See anthropic.com/legal/privacy.\n\nThe App also retrieves public book information (cover images, titles, descriptions) from the Google Books API and generates shopping links to Amazon. These requests are for book metadata and do not transmit your personal taste data."
        ),
        Section(
            heading: "Where data is stored",
            body: "Your taste data and anonymous identifier are stored using Google Cloud (Firestore) on servers operated on our behalf. Data is transmitted over encrypted connections (HTTPS/TLS)."
        ),
        Section(
            heading: "Data sharing",
            body: "We do not sell your data. We do not share your data with advertisers. We do not use your data to track you across other apps or websites. The only third parties that process data are the service providers described above (Anthropic, Google Cloud, Google Books), each acting to deliver the App\u{2019}s core functionality."
        ),
        Section(
            heading: "Your choices and rights",
            body: "•  Delete your data: the App includes a \u{201C}Delete my data\u{201D} option in settings that erases your taste history and reactions from our servers. This is immediate and cannot be undone.\n•  Stop contributing to community lists: turn off \u{201C}Contribute my likes\u{201D} in settings at any time.\n•  Access or deletion requests: if you are in a jurisdiction with data-protection rights (such as the EU under GDPR or California under the CCPA), contact us at \(AppLinks.privacyEmail) to request access to or deletion of your data."
        ),
        Section(
            heading: "Children",
            body: "Shelf is not directed at children under 13 and does not knowingly collect data from them."
        ),
        Section(
            heading: "Data retention",
            body: "We keep your taste data for as long as you use the App. If you use \u{201C}Delete my data,\u{201D} or if you delete and reinstall the App, the prior data is no longer associated with you and is removed."
        ),
        Section(
            heading: "Changes to this policy",
            body: "We may update this policy as the App evolves. Material changes will be reflected by updating the \u{201C}Last updated\u{201D} date above."
        ),
        Section(
            heading: "Contact",
            body: "Questions about this policy or your data: \(AppLinks.privacyEmail)."
        ),
    ]
}
