import Foundation
import SwiftUI
struct ReportProblemView: View {
    private var copy: SettingsContentCopy { .current }
    private var reportProblemURL: URL? { URL(string: AppLinks.current.reportProblem) }
    var body: some View {
        Form {
            Section {
                Text(copy.reportProblemDescription).font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("Support Link")) {
                if let url = reportProblemURL {
                    Link(destination: url) {
                        Label(copy.reportProblemActionTitle, systemImage: "arrow.up.right.square")
                    }
                    Text(url.absoluteString).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }.navigationTitle(AppLocalization.string("Report a Problem"))
    }
}
