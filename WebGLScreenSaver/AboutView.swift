import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) var openURL

    private var appVersionAndBuild: String {
        let version = Bundle.main
            .infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
        let build = Bundle.main
            .infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
        return "Version \(version) (\(build))"
    }

    private var copyright: String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        return "© \(year) Kosei Haruyama"
    }

    private var developerWebsite: URL {
        URL(string: "https://github.com/Harumaru169")!
    }

    private var creditsURL: URL? {
        Bundle.main.url(forResource: "Credits", withExtension: "html")!
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.tv.fill")
                .resizable()
                .foregroundStyle(.tint)
                .scaledToFit()
                .frame(width: 80)
            Text("WebGL Screen Saver")
                .font(.title)
            VStack(spacing: 6) {
                Text(appVersionAndBuild)
                Text(copyright)
            }
            .font(.callout)
            HStack(spacing: 12) {
                Button("Developer Website") {
                    NSWorkspace.shared.open(developerWebsite)
                }
                if let creditsURL {
                    Button("Acknowledgements") {
                        NSWorkspace.shared.open(creditsURL)
                    }
                }
            }
            .buttonStyle(.link)
            .foregroundStyle(.accent)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 260)
    }
}

#Preview {
    AboutView()
}
