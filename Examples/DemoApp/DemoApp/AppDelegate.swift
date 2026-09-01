import SpaceZ
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // The entire integration: one call in a debug build.
        #if DEBUG
        SpaceZDebugger.start()
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default", sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)

        let tabs = UITabBarController()
        let checkout = UINavigationController(rootViewController: CheckoutViewController())
        checkout.tabBarItem = UITabBarItem(
            title: "Checkout", image: UIImage(systemName: "creditcard"), tag: 0
        )
        let swiftUI = UINavigationController(rootViewController: SwiftUIDemoViewController())
        swiftUI.tabBarItem = UITabBarItem(
            title: "SwiftUI", image: UIImage(systemName: "swift"), tag: 1
        )
        let stress = UINavigationController(rootViewController: StressViewController())
        stress.tabBarItem = UITabBarItem(
            title: "Stress", image: UIImage(systemName: "square.stack.3d.up"), tag: 2
        )
        tabs.viewControllers = [checkout, swiftUI, stress]
        // Launch argument for automation: -initialTab 1 opens the SwiftUI tab.
        if let index = UserDefaults.standard.string(forKey: "initialTab").flatMap(Int.init),
           (0..<3).contains(index) {
            tabs.selectedIndex = index
        }

        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
    }
}
