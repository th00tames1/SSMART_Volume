import UIKit
import ARKit

func setDefaultsFromSettingsBundle() {
    
    let plistFiles = ["Root", "Mapping", "Assembling"]
    
    for plistName in plistFiles {
        //Read PreferenceSpecifiers from Root.plist in Settings.Bundle
        if let settingsURL = Bundle.main.url(forResource: plistName, withExtension: "plist", subdirectory: "Settings.bundle"),
            let settingsPlist = NSDictionary(contentsOf: settingsURL),
            let preferences = settingsPlist["PreferenceSpecifiers"] as? [NSDictionary] {

            for prefSpecification in preferences {

                if let key = prefSpecification["Key"] as? String, let value = prefSpecification["DefaultValue"] {

                    //If key doesn't exists in userDefaults then register it, else keep original value
                    if UserDefaults.standard.value(forKey: key) == nil {

                        UserDefaults.standard.set(value, forKey: key)
                        NSLog("registerDefaultsFromSettingsBundle: Set following to UserDefaults - (key: \(key), value: \(value), type: \(type(of: value)))")
                    }
                }
            }
        } else {
            NSLog("registerDefaultsFromSettingsBundle: Could not find Settings.bundle")
        }
    }
}


@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Always set Version to default
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "Version")

        setDefaultsFromSettingsBundle()

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        window = UIWindow(frame: UIScreen.main.bounds)
        
        var initialViewController: UIViewController

        // 라이다 지원을 안할 경우
        if !ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            // LiDAR를 지원하지 않는 기기에서는 에러 메시지 뷰 컨트롤러를 표시합니다.
            initialViewController = storyboard.instantiateViewController(withIdentifier: "unsupportedDeviceMessage")
        } else {
            // 'mapScene'을 루트 뷰 컨트롤러로 설정합니다.
            initialViewController = storyboard.instantiateViewController(withIdentifier: "mapScene")
        }

        window?.rootViewController = initialViewController
        window?.makeKeyAndVisible()

        return true
    }


    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
    
}

