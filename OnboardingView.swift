import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var app: AppModel
    @State private var username = ""

    private var isUsernameEmpty: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Backdrop()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "music.note.list")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Theme.gradient)

                VStack(spacing: 8) {
                    Text("Welcome to Tonal")
                        .font(.largeTitle.weight(.bold))

                    Text("Enter the Last.fm profile you want to explore.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                TextField("Last.fm username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                Button("Get Started") {
                    let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
                    app.username = trimmedUsername.isEmpty ? Config.defaultUsername : trimmedUsername
                    app.onboarded = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(isUsernameEmpty)

                Spacer()
            }
            .padding(32)
        }
        .onAppear {
            username = app.username
        }
    }
}
