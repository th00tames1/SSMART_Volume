import UIKit
import ARKit

func setDefaultsFromSettings() {
    // -----------------------------
    // [1] Blending (Online Blending)
    // -----------------------------
    UserDefaults.standard.set(true, forKey: "Blending")
    
    // -----------------------------
    // [2] Nodes Filtering
    //     plist(Root) default: false
    // -----------------------------
    UserDefaults.standard.set(false, forKey: "NodesFiltering")
    
    // -----------------------------
    // [3] HDMode
    //     plist(Mapping) default: false
    // -----------------------------
    UserDefaults.standard.set(false, forKey: "HDMode")
    
    // -----------------------------
    // [4] Smoothing
    //     plist(Mapping) default: false
    // -----------------------------
    UserDefaults.standard.set(false, forKey: "Smoothing")
    
    // -----------------------------
    // [5] Append Mode
    //     plist(Mapping) default: true
    // -----------------------------
    UserDefaults.standard.set(true, forKey: "AppendMode")
    
    // -----------------------------
    // [5-1] LidarMode
    //      plist(Mapping) default: true
    // -----------------------------
    UserDefaults.standard.set(true, forKey: "LidarMode")
    
    // ----------------------------------------------------------
    // [6] UpstreamRelocalizationAccThr
    //     plist(Mapping) default: 6.0
    // ----------------------------------------------------------
    UserDefaults.standard.set(6.0, forKey: "UpstreamRelocalizationFilteringAccThr")
    
    // -----------------------------
    // [7] TimeLimit
    //     plist(Mapping) default: "0"
    // -----------------------------
    UserDefaults.standard.set("0", forKey: "TimeLimit")
    
    // -----------------------------
    // [8] MaxFeaturesExtractedLoopClosure
    //     plist(Mapping) default: "400"
    // -----------------------------
    UserDefaults.standard.set("400", forKey: "MaxFeaturesExtractedLoopClosure")
    
    // ----------------------------------------------------
    // Mapping Parameter
    // ----------------------------------------------------
    
    // UpdateRate : default "1"
    UserDefaults.standard.set("1", forKey: "UpdateRate")
    
    // MemoryLimit : default "0"
    UserDefaults.standard.set("0", forKey: "MemoryLimit")
    
    // MaximumMotionSpeed : default "0"
    UserDefaults.standard.set("0", forKey: "MaximumMotionSpeed")
    
    // LoopClosureThreshold : default "0.11"
    UserDefaults.standard.set("0.11", forKey: "LoopClosureThreshold")
    
    // SimilarityThreshold : default "0.3"
    UserDefaults.standard.set("0.3", forKey: "SimilarityThreshold")
    
    // MinInliers : default "25"
    UserDefaults.standard.set("25", forKey: "MinInliers")
    
    // MaxOptimizationError : default "1"
    UserDefaults.standard.set("1", forKey: "MaxOptimizationError")
    
    // MaxFeaturesExtractedVocabulary : default "400"
    UserDefaults.standard.set("400", forKey: "MaxFeaturesExtractedVocabulary")
    
    // FeatureType : default "6" (BRIEF)
    UserDefaults.standard.set("6", forKey: "FeatureType")
    
    // SaveAllFramesInDatabase : default true
    UserDefaults.standard.set(true, forKey: "SaveAllFramesInDatabase")
    
    // OptimizationfromGraphEnd : default true
    UserDefaults.standard.set(true, forKey: "OptimizationfromGraphEnd")
    
    // MaximumOdometryCacheSize : default "10"
    UserDefaults.standard.set("10", forKey: "MaximumOdometryCacheSize")
    
    // GraphOptimizer : default "2" (GTSAM)
    UserDefaults.standard.set("2", forKey: "GraphOptimizer")
    
    // ProximityDetection : default true
    UserDefaults.standard.set(true, forKey: "ProximityDetection")
    
    // ArUcoMarkerDetection : default -1 (disabled)
    UserDefaults.standard.set(-1, forKey: "ArUcoMarkerDetection")
    
    // MarkerDepthErrorEstimation : default "0.04"
    UserDefaults.standard.set("0.04", forKey: "MarkerDepthErrorEstimation")
    
    // MarkerSize : default "-1"
    UserDefaults.standard.set("-1", forKey: "MarkerSize")

    // DatabaseInMemory : default true
    UserDefaults.standard.set(true, forKey: "DatabaseInMemory")
    
    // ----------------------------------------------------
    // Rendering Parameter (plist: Root)
    // ----------------------------------------------------
    
    // PointCloudDensity : default 1
    UserDefaults.standard.set(1, forKey: "PointCloudDensity")
    
    // MaxDepth : default 5.0
    UserDefaults.standard.set(5.0, forKey: "MaxDepth")
    
    // MinDepth : default 0.0
    UserDefaults.standard.set(0.0, forKey: "MinDepth")
    
    // DepthConfidence : default 1 (2: High, 1: Medium, 0: Low)
    UserDefaults.standard.set(1, forKey: "DepthConfidence")
    
    // PointSize : default 10.0
    UserDefaults.standard.set(10.0, forKey: "PointSize")
    
    // MeshAngleTolerance : default 20.0
    UserDefaults.standard.set(20.0, forKey: "MeshAngleTolerance")
    
    // MeshTriangleSize : default 2
    UserDefaults.standard.set(2, forKey: "MeshTriangleSize")
    
    // MeshDecimationFactor : default 0.0
    UserDefaults.standard.set(0.0, forKey: "MeshDecimationFactor")
    
    // BackgroundColor : default 0.8
    UserDefaults.standard.set(0.8, forKey: "BackgroundColor")
    
    // NoiseFilteringRatio : default 0.05
    UserDefaults.standard.set(0.05, forKey: "NoiseFilteringRatio")
    
    // ColorCorrectionRadius : default 0.02
    // (Root.plist에 있음)
    UserDefaults.standard.set(0.02, forKey: "ColorCorrectionRadius")
    
    // TextureResolution : default 4
    UserDefaults.standard.set(4, forKey: "TextureResolution")
    
    // SaveGPS : default true
    UserDefaults.standard.set(true, forKey: "SaveGPS")
    
    // ----------------------------------------------------
    // Assembling Parameter
    // ----------------------------------------------------
    
    // VoxelSize : default 0.01
    UserDefaults.standard.set(0.01, forKey: "VoxelSize")

    // TextureSize : default 8192
    UserDefaults.standard.set(8192, forKey: "TextureSize")

    // MaximumOutputTextures : default 1
    UserDefaults.standard.set(1, forKey: "MaximumOutputTextures")

    // NormalK : default 18
    UserDefaults.standard.set(18, forKey: "NormalK")

    // MaxTextureDistance : default 0
    UserDefaults.standard.set(0, forKey: "MaxTextureDistance")

    // MinTextureClusterSize : default 10
    UserDefaults.standard.set(10, forKey: "MinTextureClusterSize")

    // ReconstructionDepth : default 0
    UserDefaults.standard.set(0, forKey: "ReconstructionDepth")

    // ColorRadius : default 0
    UserDefaults.standard.set(0, forKey: "ColorRadius")

    // CleanMesh : default true
    UserDefaults.standard.set(true, forKey: "CleanMesh")

    // PolygonFiltering : default -1
    UserDefaults.standard.set(-1, forKey: "PolygonFiltering")
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Always set Version to default
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "Version")

        setDefaultsFromSettings()

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        window = UIWindow(frame: UIScreen.main.bounds)
        
        var initialViewController: UIViewController

        // 라이다 지원을 안할 경우
        if !ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            // Error Message View Control
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

