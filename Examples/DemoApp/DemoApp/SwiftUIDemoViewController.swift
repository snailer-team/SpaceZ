import SwiftUI
import UIKit

/// UIKit + SwiftUI mixed screen: the inspector shows the hosting view's real
/// UIView subtree *and* the reflected `SwiftUI:*` semantic tree side by side.
final class SwiftUIDemoViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "SwiftUI"
        view.backgroundColor = .systemBackground

        let hosting = UIHostingController(rootView: ProfileCard())
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }
}

struct ProfileCard: View {
    @State private var isFollowing = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("SpaceZ Astronaut")
                .font(.title2.bold())
            Text("Debugging UI since 2026")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(isFollowing ? "Following" : "Follow") {
                    isFollowing.toggle()
                }
                .buttonStyle(.borderedProminent)
                Button("Message") {}
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 20).fill(.quaternary.opacity(0.4)))
        .padding()
    }
}
