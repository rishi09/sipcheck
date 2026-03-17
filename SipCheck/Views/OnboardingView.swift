import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            onboardingPage(
                icon: "camera.fill",
                title: "Scan Any Beer Label",
                description: "Point your camera at a beer label and let SipCheck identify it instantly.",
                tag: 0
            )
            onboardingPage(
                icon: "list.bullet.clipboard",
                title: "Track What You've Tried",
                description: "Keep a personal journal of every beer you taste, with ratings and notes.",
                tag: 1
            )
            onboardingPage(
                icon: "sparkles",
                title: "Get AI Recommendations",
                description: "Receive personalized beer suggestions based on your taste preferences.",
                tag: 2
            )
            getStartedPage(tag: 3)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    private func onboardingPage(icon: String, title: String, description: String, tag: Int) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .tag(tag)
    }

    private func getStartedPage(tag: Int) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            Text("You're All Set")
                .font(.title)
                .fontWeight(.bold)
            Text("Start discovering and tracking your favorite beers.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Button(action: {
                hasCompletedOnboarding = true
            }) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .tag(tag)
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
