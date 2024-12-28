//
//  ViewController.swift
//  SlashScan
//
//  Created by HC on 9/18/24.
//
import GLKit
import ARKit
import Zip
import StoreKit

extension Array {
    func size() -> Int {
        return MemoryLayout<Element>.stride * self.count
    }
}

class ViewController: GLKViewController, ARSessionDelegate, RTABMapObserver, UIPickerViewDataSource, UIPickerViewDelegate, CLLocationManagerDelegate {
    
    private let session = ARSession()
    private var locationManager: CLLocationManager?
    private var mLastKnownLocation: CLLocation?
    private var mLastLightEstimate: CGFloat?
    
    private var context: EAGLContext?
    private var rtabmap: RTABMap?
    
    private var databases = [URL]()
    private var currentDatabaseIndex: Int = 0
    private var openedDatabasePath: URL?
    
    private var progressDialog: UIAlertController?
    var progressView : UIProgressView?
    
    var maxPolygonsPickerView: UIPickerView!
    var maxPolygonsPickerData: [Int]!
    
    private var mTotalLoopClosures: Int = 0
    private var mMapNodes: Int = 0
    private var mTimeThr: Int = 0
    private var mMaxFeatures: Int = 0
    private var mLoopThr = 0.11
    private var mDataRecording = false
    
    // UI states
    private enum State {
        case STATE_WELCOME,    // Camera/Motion off - showing only buttons open and start new scan
        STATE_CAMERA,          // Camera/Motion on - not mapping
        STATE_MAPPING,         // Camera/Motion on - mapping
        STATE_IDLE,            // Camera/Motion off
        STATE_PROCESSING,      // Camera/Motion off - post processing
        STATE_VISUALIZING,     // Camera/Motion off - Showing optimized mesh
        STATE_VISUALIZING_CAMERA,     // Camera/Motion on  - Showing optimized mesh
        STATE_EDIT,             // EDIT
        STATE_VISUALIZING_WHILE_LOADING // Camera/Motion off - Loading data while showing optimized mesh
    }
    private var mState: State = State.STATE_WELCOME;
    private func getStateString(state: State) -> String {
        switch state {
        case .STATE_WELCOME:
            return "Welcome"
        case .STATE_CAMERA:
            return "Camera Preview"
        case .STATE_MAPPING:
            return mDataRecording ? "Data Recording" : "Mapping"
        case .STATE_PROCESSING:
            return "Processing"
        case .STATE_VISUALIZING:
            return "Visualizing"
        case .STATE_VISUALIZING_CAMERA:
            return "Visualizing with Camera"
        case .STATE_VISUALIZING_WHILE_LOADING:
            return "Visualizing while Loading"
        case .STATE_EDIT:
            return "Mesuring Data"
        default: // IDLE
            return "Idle"
        }
    }
    
    private var depthSupported: Bool = false
    
    private var viewMode: Int = 0 // 0=Cloud, 1=Mesh, 2=Textured Mesh
    private var cameraMode: Int = 1
    
    private var statusShown: Bool = true
    private var debugShown: Bool = false
    private var mapShown: Bool = true
    private var odomShown: Bool = true
    private var graphShown: Bool = true
    private var gridShown: Bool = true
    private var optimizedGraphShown: Bool = true
    private var wireframeShown: Bool = false
    private var backfaceShown: Bool = false
    private var lightingShown: Bool = false
    private var mHudVisible: Bool = true
    private var mLastTimeHudShown: DispatchTime = .now()
    private var mMenuOpened: Bool = false
    private var manualView: UIView?
    private var isProjectPopupShowing = false
    private var isCropping: Bool = false
    
    private var editRectStart: CGPoint?
    private var editRectCurrent: CGRect?
    
    @IBOutlet weak var stopButton: UIButton!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var saveButton: UIButton!
    @IBOutlet weak var menuButton: UIButton!
    @IBOutlet weak var viewButton: UIButton!
    @IBOutlet weak var libraryButton: UIButton!
    @IBOutlet weak var projectButton: UIButton!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var closeVisualizationButton: UIButton!
    @IBOutlet weak var stopCameraButton: UIButton!
    @IBOutlet weak var editButton: UIButton!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var mapButton: UIButton!
    @IBOutlet weak var infoLabel: UILabel!
    @IBOutlet weak var titleContent: UITextField!
    @IBOutlet weak var cropButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var editsaveButton: UIButton!
    @IBOutlet weak var toastLabel: UILabel!
    //    @IBOutlet weak var orthoDistanceSlider: UISlider!{
    //        didSet{
    //            orthoDistanceSlider.transform = CGAffineTransform(rotationAngle: CGFloat(-Double.pi/2))
    //        }
    //    }
    //    @IBOutlet weak var orthoGridSlider: UISlider!
    
    let RTABMAP_TMP_DB = "slashscan.tmp.db"
    let RTABMAP_RECOVERY_DB = "slashscan.tmp.recovery.db"
    let RTABMAP_EXPORT_DIR = "Export"

    func getDocumentDirectory() -> URL {
        if let projectPath = UserDefaults.standard.string(forKey: "SelectedProjectFolder"),
           !projectPath.isEmpty {
            let projectURL = URL(fileURLWithPath: projectPath)
            // 해당 폴더가 실제로 존재하는지 확인 (옵션)
            if FileManager.default.fileExists(atPath: projectURL.path) {
                selectedProjectFolderURL = projectURL
                return projectURL
            }
        }
        // 프로젝트 폴더가 없거나 설정되지 않았을 경우 기본 DocumentDirectory 반환
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    
    func getTmpDirectory() -> URL {
       return URL(fileURLWithPath: NSTemporaryDirectory())
    }
    
    @objc func defaultsChanged(){
        updateDisplayFromDefaults()
    }
    
    func showToast(message: String, seconds: Double) {
        if !self.toastLabel.isHidden {
            self.toastLabel.isHidden = true
        }
        self.toastLabel.text = message
        self.toastLabel.isHidden = false

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + seconds) {
            if self.toastLabel.text == message {
                self.toastLabel.isHidden = true
            }
        }
    }


    func resetNoTouchTimer(_ showHud: Bool = false) {
        if(showHud)
        {
            print("Show HUD")
            mMenuOpened = false
            mHudVisible = true
            setNeedsStatusBarAppearanceUpdate()
            updateState(state: self.mState)
        }
        else if(mState != .STATE_WELCOME && mState != .STATE_CAMERA && presentedViewController as? UIAlertController == nil && !mMenuOpened)
        {
            print("Hide HUD")
            self.mHudVisible = false
            self.setNeedsStatusBarAppearanceUpdate()
            self.updateState(state: self.mState)
        }
    }
    
    // MARK: TouchAction
    func TouchAction(_ showHud: Bool = false) {
        if(showHud)
        {
            print("Show HUD")
            mMenuOpened = false
            mHudVisible = true
            setNeedsStatusBarAppearanceUpdate()
            updateState(state: self.mState)
        }
        else if(presentedViewController as? UIAlertController == nil && !mMenuOpened)
        {
            print("Hide HUD when click")
            self.mHudVisible = false
            self.setNeedsStatusBarAppearanceUpdate()
            self.updateState(state: self.mState)
        }
    }
    
    // MARK: ViewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        self.toastLabel.isHidden = true
        session.delegate = self
        
        depthSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        
        rtabmap = RTABMap()
        rtabmap?.setupCallbacksWithCPP()
        
        context = EAGLContext(api: .openGLES2)
        EAGLContext.setCurrent(context)
        
        if let view = self.view as? GLKView, let context = context {
            view.context = context
            delegate = self
            rtabmap?.initGlContent()
        }
        
        menuButton.showsMenuAsPrimaryAction = true
        viewButton.showsMenuAsPrimaryAction = true
        statusLabel.numberOfLines = 0
        statusLabel.text = ""
        infoLabel.text = ""
        titleContent.text = ""
        
        updateDatabases()
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped(_:)))
        singleTap.numberOfTapsRequired = 1
        view.addGestureRecognizer(singleTap)
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appMovedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        
        rtabmap!.addObserver(self)
        
        registerSettingsBundle()
        updateDisplayFromDefaults()
        
        maxPolygonsPickerView = UIPickerView(frame: CGRect(x: 10, y: 50, width: 250, height: 150))
        maxPolygonsPickerView.delegate = self
        maxPolygonsPickerView.dataSource = self

        // This is where you can set your min/max values
        let minNum = 0
        let maxNum = 9
        maxPolygonsPickerData = Array(stride(from: minNum, to: maxNum + 1, by: 1))
        
//        orthoDistanceSlider.setValue(80, animated: false)
//        orthoGridSlider.setValue(180, animated: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateState(state: self.mState)
        }
        
        DispatchQueue.main.async {
            self.showProjectSelectionPopup(cancel: false)
        }
        
        setupManualView()
    }
    
    var selectedProjectFolderURL: URL? {
        didSet {
            // 폴더가 설정될 때마다 getDocumentDirectory()에서 해당 폴더를 반환하도록 함
        }
    }
    
    func showProjectSelectionPopup(cancel: Bool) {
        isProjectPopupShowing = true
        let cancel = cancel
        let alert = UIAlertController(title: "Select Project Folder", message: "Data will be saved in the project folder.", preferredStyle: .alert)

        let newProjectAction = UIAlertAction(title: "Create New Folder", style: .default) { _ in
            self.showNewProjectNameInputPopup()
        }

        let browseProjectAction = UIAlertAction(title: "Browse Folder", style: .default) { _ in
            self.showBrowseProjectPopup()
        }
        
        let editProjectAction = UIAlertAction(title: "Edit Folder", style: .default) { _ in
            self.showEditProjectPopup()
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .destructive) { _ in
            self.dismissProjectPopup()
        }
        
        if #available(iOS 15.0, *) {
            if let newProjectIcon = UIImage(systemName: "document.badge.plus") {
                newProjectAction.setValue(newProjectIcon, forKey: "image")
            }
            if let browseProjectIcon = UIImage(systemName: "document") {
                browseProjectAction.setValue(browseProjectIcon, forKey: "image")
            }
            if let editProjectIcon = UIImage(systemName: "square.and.pencil") {
                editProjectAction.setValue(editProjectIcon, forKey: "image")
            }
        }
        
        alert.addAction(newProjectAction)
        alert.addAction(browseProjectAction)
        if(cancel == true){
            alert.addAction(editProjectAction)
            alert.addAction(cancelAction)
        }
        self.present(alert, animated: true)
    }
    
    // 프로젝트 팝업 종료 시 호출
    func dismissProjectPopup() {
        isProjectPopupShowing = false
        // 현재 상태가 WELCOME이면 매뉴얼 다시 표시
        if mState == .STATE_WELCOME {
            manualView?.isHidden = false
        }
    }
    
    // New Project 폴더명 입력 팝업
    func showNewProjectNameInputPopup() {
        let alert = UIAlertController(title: "New Project", message: "Enter project folder name", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "ProjectName"
        }
        
        let createAction = UIAlertAction(title: "Create", style: .default) { _ in
            if let folderName = alert.textFields?.first?.text, !folderName.isEmpty {
                self.createProjectFolder(folderName: folderName)
            } else {
                // 폴더명을 입력하지 않은 경우 다시 입력받거나 에러 처리
                self.showToast(message: "Folder name cannot be empty.", seconds: 2)
            }
            self.dismissProjectPopup()
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            if self.selectedProjectFolderURL == nil {
                self.showProjectSelectionPopup(cancel: false)
            } else {
                self.dismissProjectPopup()
            }
        }
        
        alert.addAction(createAction)
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true)
    }
    
    func showBrowseProjectPopup() {
        // Documents 디렉토리 내 폴더 목록 가져오기
        let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        var folders: [URL] = []
        do {
            let items = try FileManager.default.contentsOfDirectory(at: docURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            folders = items.filter { $0.hasDirectoryPath }
        } catch {
            print("Error reading directories: \(error)")
            self.dismissProjectPopup()
        }
        
        if folders.isEmpty {
            self.showToast(message: "No existing project folders found.", seconds: 2)
            self.dismissProjectPopup()
            return
        }
        
        let alert = UIAlertController(title: "Browse Project", message: "Select a project folder", preferredStyle: .alert)
        
        for folderURL in folders {
            let folderName = folderURL.lastPathComponent
            let folderAction = UIAlertAction(title: folderName, style: .default) { _ in
                
                self.dismissProjectPopup()
                // 선택한 폴더로 getDocumentDirectory 설정
                self.selectedProjectFolderURL = folderURL
                if let folderURL = self.selectedProjectFolderURL {
                    UserDefaults.standard.setValue(folderURL.path, forKey: "SelectedProjectFolder")
                    self.updateDatabases()
                    if self.databases.isEmpty {
                        self.libraryButton.isEnabled = false
                    } else {
                        self.libraryButton.isEnabled = true
                    }
                }
                self.showToast(message: "Selected project: \(folderName)", seconds: 4)
            }
            alert.addAction(folderAction)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            if self.selectedProjectFolderURL == nil {
                self.showProjectSelectionPopup(cancel: false)
            } else {
                self.dismissProjectPopup()
            }
        }
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true)
    }
    
    func createProjectFolder(folderName: String) {
        let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectFolderURL = docURL.appendingPathComponent(folderName)
        
        // 폴더가 이미 존재하는지 체크
        if FileManager.default.fileExists(atPath: projectFolderURL.path) {
            // 폴더 존재 시, 덮어쓸 것인지 묻는 팝업
            let alert = UIAlertController(title: "File Already Exists", message: "Do you want to overwrite the existing file?", preferredStyle: .alert)
            let yes = UIAlertAction(title: "Yes", style: .default) { _ in
                // 기존 폴더 삭제
                do {
                    try FileManager.default.removeItem(at: projectFolderURL)
                    // 폴더 다시 생성
                    try FileManager.default.createDirectory(at: projectFolderURL, withIntermediateDirectories: false)
                    self.selectedProjectFolderURL = projectFolderURL
                    if let projectfolderURL = self.selectedProjectFolderURL {
                        UserDefaults.standard.setValue(projectfolderURL.path, forKey: "SelectedProjectFolder")
                    }
                    self.showToast(message: "Project folder '\(folderName)' overwritten.", seconds: 2)
                } catch {
                    self.showToast(message: "Failed to overwrite folder: \(error)", seconds: 2)
                }
            }
            let no = UIAlertAction(title: "No", style: .cancel) { _ in
                // 취소
            }
            alert.addAction(yes)
            alert.addAction(no)
            self.present(alert, animated: true, completion: nil)
            
        } else {
            // 폴더가 없으므로 새로 생성
            do {
                try FileManager.default.createDirectory(at: projectFolderURL, withIntermediateDirectories: false)
                self.selectedProjectFolderURL = projectFolderURL
                if let projectfolderURL = self.selectedProjectFolderURL {
                    UserDefaults.standard.setValue(projectfolderURL.path, forKey: "SelectedProjectFolder")
                }
                self.showToast(message: "Project folder '\(folderName)' created.", seconds: 2)
            } catch {
                self.showToast(message: "Failed to create folder: \(error)", seconds: 2)
            }
        }
    }

    private func setupManualView() {
        // manualView 생성
        let manualView = UIView()
        manualView.backgroundColor = .white
        manualView.layer.cornerRadius = 10
        manualView.layer.masksToBounds = true
        manualView.translatesAutoresizingMaskIntoConstraints = false
        
        self.view.addSubview(manualView)
        self.manualView = manualView
        
        // manualView를 화면 가운데에 배치
        NSLayoutConstraint.activate([
            manualView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            manualView.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            manualView.widthAnchor.constraint(equalToConstant: 300),
            manualView.heightAnchor.constraint(equalToConstant: 400)
        ])
    
        let verticalStack = UIStackView()
        verticalStack.axis = .vertical
        verticalStack.alignment = .fill
        verticalStack.distribution = .equalSpacing
        verticalStack.spacing = 20
        verticalStack.translatesAutoresizingMaskIntoConstraints = false
        
        manualView.addSubview(verticalStack)
        
        NSLayoutConstraint.activate([
            verticalStack.topAnchor.constraint(equalTo: manualView.topAnchor, constant: 20),
            verticalStack.leadingAnchor.constraint(equalTo: manualView.leadingAnchor, constant: 20),
            verticalStack.trailingAnchor.constraint(equalTo: manualView.trailingAnchor, constant: -20),
            verticalStack.bottomAnchor.constraint(equalTo: manualView.bottomAnchor, constant: -20)
        ])

        // 예시용 4단계 생성
        let stepView1 = createManualStep(
            image: UIImage(systemName: "plus.circle.fill")!.withRenderingMode(.alwaysTemplate),
            text: "Step 1: Press the blue button on the right to prepare recording",
            tintColor: .systemBlue
        )
        verticalStack.addArrangedSubview(stepView1)

        let stepView2 = createManualStep(
            image: UIImage(systemName: "record.circle")!.withRenderingMode(.alwaysTemplate),
            text: "Step 2: Press the red button to start recording.",
            tintColor: .systemRed
        )
        verticalStack.addArrangedSubview(stepView2)

        let stepView3 = createManualStep(
            image: UIImage(systemName: "cube.transparent")!.withRenderingMode(.alwaysTemplate),
            text: "Step 3: Press the yellow button to crop and measure the acquired data.",
            tintColor: .systemYellow
        )
        verticalStack.addArrangedSubview(stepView3)

        let stepView4 = createManualStep(
            image: UIImage(systemName: "map.circle")!.withRenderingMode(.alwaysTemplate),
            text: "Open the map to view and manage the acquired data.",
            tintColor: .systemGreen
        )
        verticalStack.addArrangedSubview(stepView4)
        
        // 초기에는 STATE_WELCOME 아닐 경우 hidden 처리하기 위해 숨겨둠
        manualView.isHidden = true
    }

    private func createManualStep(image: UIImage, text: String, tintColor: UIColor) -> UIView {
        let horizontalStack = UIStackView()
        horizontalStack.axis = .horizontal
        horizontalStack.alignment = .center
        horizontalStack.spacing = 10
        
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = tintColor // 이미지 색상 변경
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 40),
            imageView.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textColor = .black
        label.font = UIFont.systemFont(ofSize: 14)
        
        horizontalStack.addArrangedSubview(imageView)
        horizontalStack.addArrangedSubview(label)
        
        return horizontalStack
    }

    
    func showEditProjectPopup() {
        isProjectPopupShowing = true

        let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        var folders: [URL] = []
        do {
            let items = try FileManager.default.contentsOfDirectory(at: docURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            // 폴더만 추출
            folders = items.filter { $0.hasDirectoryPath }
        } catch {
            print("Error reading directories: \(error)")
            self.dismissProjectPopup()
            return
        }

        if folders.isEmpty {
            self.showToast(message: "No existing project folders found.", seconds: 2)
            self.dismissProjectPopup()
            return
        }

        let alert = UIAlertController(title: "Edit Project", message: "Select a project folder to edit", preferredStyle: .alert)

        for folderURL in folders {
            let folderName = folderURL.lastPathComponent
            let folderAction = UIAlertAction(title: folderName, style: .default) { _ in
                // 프로젝트 폴더 선택 시 Rename/Delete 옵션 팝업 표시
                self.showEditOptionsForProject(folderURL: folderURL)
            }
            alert.addAction(folderAction)
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .destructive) { _ in
            self.dismissProjectPopup()
        }
        alert.addAction(cancelAction)

        self.present(alert, animated: true, completion: nil)
    }

    // 프로젝트에 대해 Rename/Delete를 할 수 있는 팝업 표시
    func showEditOptionsForProject(folderURL: URL) {
        let alert = UIAlertController(title: folderURL.lastPathComponent, message: "Select an option", preferredStyle: .alert)

        let renameAction = UIAlertAction(title: "Rename", style: .default) { _ in
            self.showRenameProjectPopup(folderURL: folderURL)
        }

        let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { _ in
            // 삭제 확인 팝업
            self.showDeleteConfirmPopup(folderURL: folderURL)
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)

        alert.addAction(renameAction)
        alert.addAction(deleteAction)
        alert.addAction(cancelAction)

        self.present(alert, animated: true, completion: nil)
    }

    // Rename 팝업 표시
    func showRenameProjectPopup(folderURL: URL) {
        let alert = UIAlertController(title: "Rename Project", message: "Enter new project name", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "NewProjectName"
            textField.text = folderURL.lastPathComponent
        }

        let renameAction = UIAlertAction(title: "Rename", style: .default) { _ in
            if let newName = alert.textFields?.first?.text, !newName.isEmpty {
                self.renameProjectFolder(oldURL: folderURL, newName: newName)
            } else {
                self.showToast(message: "Project name cannot be empty.", seconds: 2)
            }
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)

        alert.addAction(renameAction)
        alert.addAction(cancelAction)

        self.present(alert, animated: true, completion: nil)
    }

    // 실제 폴더 Rename 동작
    func renameProjectFolder(oldURL: URL, newName: String) {
        let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let newURL = docURL.appendingPathComponent(newName)

        if FileManager.default.fileExists(atPath: newURL.path) {
            // 이미 동일 이름 폴더가 있으면 덮어쓸지 묻기
            let alert = UIAlertController(title: "File Already Exists", message: "Do you want to overwrite the existing file?", preferredStyle: .alert)
            let yesAction = UIAlertAction(title: "Yes", style: .default) { _ in
                do {
                    // 기존 폴더 삭제
                    try FileManager.default.removeItem(at: newURL)
                    // 폴더 이름 변경
                    try FileManager.default.moveItem(at: oldURL, to: newURL)
                    self.showToast(message: "Project renamed and overwritten to '\(newName)'", seconds: 2)
                } catch {
                    self.showToast(message: "Failed to overwrite: \(error)", seconds: 2)
                }
            }
            let noAction = UIAlertAction(title: "No", style: .cancel, handler: nil)
            alert.addAction(yesAction)
            alert.addAction(noAction)
            self.present(alert, animated: true, completion: nil)
        } else {
            // 바로 이름 변경
            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                self.showToast(message: "Project renamed to '\(newName)'", seconds: 2)
            } catch {
                self.showToast(message: "Failed to rename: \(error)", seconds: 2)
            }
        }
        self.updateDatabases()
    }

    // 삭제 확인 팝업
    func showDeleteConfirmPopup(folderURL: URL) {
        let alert = UIAlertController(title: "Delete Project", message: "Are you sure you want to delete '\(folderURL.lastPathComponent)'?", preferredStyle: .alert)
        let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.deleteProjectFolder(folderURL: folderURL)
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)

        alert.addAction(deleteAction)
        alert.addAction(cancelAction)

        self.present(alert, animated: true, completion: nil)
    }

    // 실제 폴더 삭제
    func deleteProjectFolder(folderURL: URL) {
        do {
            try FileManager.default.removeItem(at: folderURL)
            self.showToast(message: "Project '\(folderURL.lastPathComponent)' deleted.", seconds: 2)
        } catch {
            self.showToast(message: "Failed to delete: \(error)", seconds: 2)
        }
        self.updateDatabases()
    }
    
    func progressUpdated(_ rtabmap: RTABMap, count: Int, max: Int) {
        DispatchQueue.main.async {
            self.progressView?.setProgress(Float(count)/Float(max), animated: true)
        }
    }
    func initEventReceived(_ rtabmap: RTABMap, status: Int, msg: String) {
        DispatchQueue.main.async {
            var optimizedMeshDetected = 0

            if(msg == "Loading optimized cloud...done.")
            {
                optimizedMeshDetected = 1;
            }
            else if(msg == "Loading optimized mesh...done.")
            {
                optimizedMeshDetected = 2;
            }
            else if(msg == "Loading optimized texture mesh...done.")
            {
                optimizedMeshDetected = 3;
            }
            if(optimizedMeshDetected > 0)
            {
                if(optimizedMeshDetected==1)
                {
                    self.setMeshRendering(viewMode: 0)
                }
                else if(optimizedMeshDetected==2)
                {
                    self.setMeshRendering(viewMode: 1)
                }
                else // isOBJ
                {
                    self.setMeshRendering(viewMode: 2)
                }

                self.updateState(state: .STATE_VISUALIZING_WHILE_LOADING);
                self.setGLCamera(type: 2);
                
                self.dismiss(animated: true)
                self.showToast(message: "Optimized mesh detected in the database, it is shown while the database is loading...", seconds: 3)
            }

            let usedMem = self.getMemoryUsage()
            self.statusLabel.text =
                "Status: " + (status == 1 && msg.isEmpty ? self.mState == State.STATE_CAMERA ? "Camera Preview" : "Idle" : msg) + "\n" +
                "Memory Usage: \(usedMem) MB"
        }
    }

    func statsUpdated(_ rtabmap: RTABMap,
                      nodes: Int,
                      words: Int,
                      points: Int,
                      polygons: Int,
                      updateTime: Float,
                      loopClosureId: Int,
                      highestHypId: Int,
                      databaseMemoryUsed: Int,
                      inliers: Int,
                      matches: Int,
                      featuresExtracted: Int,
                      hypothesis: Float,
                      nodesDrawn: Int,
                      fps: Float,
                      rejected: Int,
                      rehearsalValue: Float,
                      optimizationMaxError: Float,
                      optimizationMaxErrorRatio: Float,
                      distanceTravelled: Float,
                      fastMovement: Int,
                      landmarkDetected: Int,
                      x: Float,
                      y: Float,
                      z: Float,
                      roll: Float,
                      pitch: Float,
                      yaw: Float)
    {
        let usedMem = self.getMemoryUsage()
        
        if(loopClosureId > 0)
        {
            mTotalLoopClosures += 1;
        }
        let previousNodes = mMapNodes
        mMapNodes = nodes;
        
        let formattedDate = Date().getFormattedDate(format: "yyyy-MM-dd HH:mm:ss")

        DispatchQueue.main.async {
            
            if(self.mMapNodes>0 && previousNodes==0 && self.mState != .STATE_MAPPING)
            {
                self.updateState(state: self.mState) // refesh menus and actions
            }
            var gpsString = "\n"
            if(UserDefaults.standard.bool(forKey: "SaveGPS"))
            {
                if let databasePath = self.openedDatabasePath {
                    let csvFileName = (databasePath.lastPathComponent as NSString).deletingPathExtension + ".csv"
                    let csvPath = databasePath.deletingLastPathComponent().appendingPathComponent(csvFileName)
                    
                    let fileExists = FileManager.default.fileExists(atPath: csvPath.path)
                    let coordinates = self.readCSVCoordinates(fileName: csvFileName)
                    
                    if fileExists {
                        // CSV 존재
                        if let coords = coordinates {
                            // CSV에서 좌표값이 있을 경우
                            gpsString = String(format: "GPS: %.6f, %.6f, %.2fm\n",
                                               coords.latitude,
                                               coords.longitude,
                                               coords.altitude)
                        } else {
                            // CSV는 있으나 좌표값을 파싱하지 못함 (좌표값 없음)
                            gpsString = "GPS: [not available]\n"
                        }
                    } else {
                        // CSV가 존재하지 않을 경우 현재 위치 정보 활용
                        if(self.mLastKnownLocation != nil)
                        {
                            if let lastLocation = self.mLastKnownLocation {
                                let secondsOld = (Date().timeIntervalSince1970 - lastLocation.timestamp.timeIntervalSince1970)
                                var bearing = 0.0
                                if(lastLocation.course > 0.0) {
                                    bearing = lastLocation.course
                                }
                                gpsString = String(format: "GPS: %.2f %.2f %.2fm %ddeg %.0fm [%d sec old]\n",
                                                   lastLocation.coordinate.longitude,
                                                   lastLocation.coordinate.latitude,
                                                   lastLocation.altitude,
                                                   Int(bearing),
                                                   lastLocation.horizontalAccuracy,
                                                   Int(secondsOld));
                            }
                        } else {
                            gpsString = "GPS: [not available]\n"
                        }
                    }
                }
                else if(self.mLastKnownLocation != nil){
                    if let lastLocation = self.mLastKnownLocation {
                        let secondsOld = (Date().timeIntervalSince1970 - lastLocation.timestamp.timeIntervalSince1970)
                        var bearing = 0.0
                        if(lastLocation.course > 0.0) {
                            bearing = lastLocation.course
                        }
                        gpsString = String(format: "GPS: %.2f %.2f %.2fm %ddeg %.0fm [%d sec old]\n",
                                           lastLocation.coordinate.longitude,
                                           lastLocation.coordinate.latitude,
                                           lastLocation.altitude,
                                           Int(bearing),
                                           lastLocation.horizontalAccuracy,
                                           Int(secondsOld));
                    }
                }
                else
                {
                    gpsString = "GPS: [not available?????]\n"
                }
            }
            self.statusLabel.text = ""
            var projectName: String
            let directory = self.getDocumentDirectory()
            if directory.isFileURL {
                projectName = directory.lastPathComponent
            } else {
                projectName = ""
            }

            var dataName: String
            if let databasePath = self.openedDatabasePath {
                dataName = databasePath.lastPathComponent
            } else {
                dataName = ""
            }

            if self.statusShown {
                self.statusLabel.text =
                    self.statusLabel.text! +
                    "Project: \(projectName)\n" +
                    "File Name: \(dataName)\n" +
                    gpsString +
                    "Status: \(self.getStateString(state: self.mState))\n" +
                    "Memory Usage : \(usedMem) MB\n"
            }
            if self.debugShown {
                self.statusLabel.text =
                    self.statusLabel.text! + "\n"
                var lightString = "\n"
                if(self.mLastLightEstimate != nil)
                {
                    lightString = String("Light (lm): \(Int(self.mLastLightEstimate!))\n")
                }
                
                self.statusLabel.text =
                    self.statusLabel.text! +
                    gpsString + //gps
                    lightString + //env sensors
                    "Time: \(formattedDate)\n" +
                    "Nodes (WM): \(nodes) (\(nodesDrawn) shown)\n" +
                    "Words: \(words)\n" +
                    "Database (MB): \(databaseMemoryUsed)\n" +
                    "Number of points: \(points)\n" +
                    "Polygons: \(polygons)\n" +
                    "Update time (ms): \(Int(updateTime)) / \(self.mTimeThr==0 ? "No Limit" : String(self.mTimeThr))\n" +
                    "Features: \(featuresExtracted) / \(self.mMaxFeatures==0 ? "No Limit" : (self.mMaxFeatures == -1 ? "Disabled" : String(self.mMaxFeatures)))\n" +
                    "Rehearsal (%): \(Int(rehearsalValue*100))\n" +
                    "Loop closures: \(self.mTotalLoopClosures)\n" +
                    "Inliers: \(inliers)\n" +
                    "Hypothesis (%): \(Int(hypothesis*100)) / \(Int(self.mLoopThr*100)) (\(loopClosureId>0 ? loopClosureId : highestHypId))\n" +
                    String(format: "FPS (rendering): %.1f Hz\n", fps) +
                    String(format: "Travelled distance: %.2f m\n", distanceTravelled) +
                    String(format: "Pose (x,y,z): %.2f %.2f %.2f", x, y, z)
            }
        }
    }

    func cameraInfoEventReceived(_ rtabmap: RTABMap, type: Int, key: String, value: String) {
        if(self.debugShown && key == "UpstreamRelocationFiltered")
        {
            DispatchQueue.main.async {
                self.dismiss(animated: true)
                self.showToast(message: "ARKit re-localization filtered because an acceleration of \(value) has been detected, which is over current threshold set in the settings.", seconds: 3)
            }
        }
    }
    
    func getMemoryUsage() -> UInt64 {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return taskInfo.resident_size / (1024*1024)
        }
        else {
            print("Error with task_info(): " +
                (String(cString: mach_error_string(kerr), encoding: String.Encoding.ascii) ?? "unknown error"))
            return 0
        }
    }
    
    @objc func appMovedToBackground() {
        if(mState == .STATE_VISUALIZING_CAMERA || mState == .STATE_MAPPING || mState == .STATE_CAMERA)
        {
            stopMapping(ignoreSaving: true)
        }
    }
    
    @objc func appMovedToForeground() {
        updateDisplayFromDefaults()
    }
    
    func setMeshRendering(viewMode: Int)
    {
        switch viewMode {
        case 0:
            self.rtabmap?.setMeshRendering(enabled: false, withTexture: false) // Point Cloud
        case 1:
            self.rtabmap?.setMeshRendering(enabled: true, withTexture: false) // Mesh Rendering
        default:
            self.rtabmap?.setMeshRendering(enabled: true, withTexture: true) // Textured Mesh Rendering
        }
        self.viewMode = viewMode
        updateState(state: mState)
    }
    
    func setGLCamera(type: Int)
    {
        cameraMode = type
        rtabmap!.setCamera(type: type);
    }
    
    func startCamera()
    {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: // The user has previously granted access to the camera.
                print("Start Camera")
                rtabmap!.startCamera()
                let configuration = ARWorldTrackingConfiguration()
                var message = ""
                if(!UserDefaults.standard.bool(forKey: "LidarMode"))
                {
                    message = "LiDAR is disabled (Settings->Mapping->LiDAR Mode = OFF), only tracked features will be mapped."
                    self.setMeshRendering(viewMode: 0)
                }
                else if !depthSupported
                {
                    message = "The device does not have a LiDAR, only tracked features will be mapped. A LiDAR is required for accurate 3D reconstruction."
                    self.setMeshRendering(viewMode: 0)
                }
                else
                {
                    configuration.frameSemantics = .sceneDepth
                }
                
                session.run(configuration, options: [.resetSceneReconstruction, .resetTracking, .removeExistingAnchors])
                
                switch mState {
                case .STATE_VISUALIZING:
                    updateState(state: .STATE_VISUALIZING_CAMERA)
                default:
                    locationManager?.startUpdatingLocation()
                    self.setMeshRendering(viewMode: 0)
                    updateState(state: .STATE_CAMERA)
                }
                
                if(!message.isEmpty)
                {
                    let alertController = UIAlertController(title: "Start Camera", message: message, preferredStyle: .alert)
                    let okAction = UIAlertAction(title: "OK", style: .default) { (action) in
                    }
                    alertController.addAction(okAction)
                    present(alertController, animated: true)
                }
            
            case .notDetermined: // The user has not yet been asked for camera access.
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        DispatchQueue.main.async {
                            self.startCamera()
                        }
                    }
                }
            
        default:
            let alertController = UIAlertController(title: "Camera Disabled", message: "Camera permission is required to start the camera. You can enable it in Settings.", preferredStyle: .alert)

            let settingsAction = UIAlertAction(title: "Settings", style: .default) { (action) in
                guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
                    return
                }
                if UIApplication.shared.canOpenURL(settingsUrl) {
                    UIApplication.shared.open(settingsUrl, completionHandler: { (success) in
                        print("Settings opened: \(success)") // Prints true
                    })
                }
            }
            alertController.addAction(settingsAction)
            
            let okAction = UIAlertAction(title: "Ignore", style: .default) { (action) in
            }
            alertController.addAction(okAction)
            
            present(alertController, animated: true)
        }
    }
    
    private func updateState(state: State)
    {
        print("State: \(state)")
        
        if(mState != state)
        {
            mState = state;
            TouchAction(true)
            return
        }
        
        mState = state;
        
        // STATE_WELCOME일 때, 프로젝트 팝업이 떠있지 않으면 매뉴얼 표시
        if state == .STATE_WELCOME && !isProjectPopupShowing {
            manualView?.isHidden = false
        } else {
            manualView?.isHidden = true
        }

        var actionNewScanEnabled: Bool
        var actionNewDataRecording: Bool
        var actionSaveEnabled: Bool
        var actionResumeEnabled: Bool
        var actionExportEnabled: Bool
        var actionOptimizeEnabled: Bool
        var actionSettingsEnabled: Bool
        
        switch mState {
        case .STATE_CAMERA:
            projectButton.isHidden = !mHudVisible
            libraryButton.isHidden = !mHudVisible
            menuButton.isHidden = !mHudVisible
            viewButton.isHidden = !mHudVisible
            startButton.isHidden = true
            recordButton.isHidden = false
            stopButton.isHidden = true
            saveButton.isHidden = true
            editButton.isHidden = true
            mapButton.isHidden = true
            closeVisualizationButton.isHidden = true
            stopCameraButton.isHidden = false
//            orthoDistanceSlider.isHidden = true
//            orthoGridSlider.isHidden = viewMode != 0 || !mHudVisible
            titleContent.isHidden = true
            infoLabel.isHidden = !mHudVisible
            actionNewScanEnabled = !mDataRecording
            actionNewDataRecording = mDataRecording
            actionSaveEnabled = false
            actionResumeEnabled = false
            actionExportEnabled = false
            actionOptimizeEnabled = false
            actionSettingsEnabled = false
            cropButton.isHidden = true
            cancelButton.isHidden = true
            editsaveButton.isHidden = true
        case .STATE_MAPPING:
            projectButton.isHidden = !mHudVisible
            libraryButton.isHidden = !mHudVisible
            menuButton.isHidden = !mHudVisible
            viewButton.isHidden = !mHudVisible
            startButton.isHidden = true
            recordButton.isHidden = true
            stopButton.isHidden = false
            saveButton.isHidden = true
            editButton.isHidden = true
            mapButton.isHidden = true
            closeVisualizationButton.isHidden = true
            stopCameraButton.isHidden = true
            infoLabel.isHidden = !mHudVisible
//            orthoDistanceSlider.isHidden = true
//            orthoGridSlider.isHidden = viewMode != 0 || !mHudVisible
            titleContent.isHidden = true
            actionNewScanEnabled = !mDataRecording
            actionNewDataRecording = mDataRecording
            actionSaveEnabled = false
            actionResumeEnabled = false
            actionExportEnabled = false
            actionOptimizeEnabled = false
            actionSettingsEnabled = false
            cropButton.isHidden = true
            cancelButton.isHidden = true
            editsaveButton.isHidden = true
        case .STATE_PROCESSING,
             .STATE_VISUALIZING_WHILE_LOADING,
             .STATE_VISUALIZING_CAMERA:
            projectButton.isHidden = true
            libraryButton.isHidden = true
            menuButton.isHidden = true
            viewButton.isHidden = true
            startButton.isHidden = true
            recordButton.isHidden = true
            stopButton.isHidden = true
            saveButton.isHidden = true
            infoLabel.isHidden = true
            editButton.isHidden = true
            mapButton.isHidden = true
            closeVisualizationButton.isHidden = true
            stopCameraButton.isHidden = mState != .STATE_VISUALIZING_CAMERA
//            orthoDistanceSlider.isHidden = true
//            orthoGridSlider.isHidden = true
            titleContent.isHidden = true
            actionNewScanEnabled = false
            actionNewDataRecording = false
            actionSaveEnabled = false
            actionResumeEnabled = false
            actionExportEnabled = false
            actionOptimizeEnabled = false
            actionSettingsEnabled = false
            cropButton.isHidden = true
            cancelButton.isHidden = true
            editsaveButton.isHidden = true
        case .STATE_VISUALIZING:
            projectButton.isHidden = !mHudVisible
            libraryButton.isHidden = !mHudVisible
            menuButton.isHidden = !mHudVisible
            viewButton.isHidden = !mHudVisible
            startButton.isHidden = !mHudVisible
            recordButton.isHidden = true
            stopButton.isHidden = true
            saveButton.isHidden = true
            editButton.isHidden = !mHudVisible
            mapButton.isHidden = !mHudVisible
            closeVisualizationButton.isHidden = true
            stopCameraButton.isHidden = true
//            orthoDistanceSlider.isHidden = true
//            orthoGridSlider.isHidden = true
            titleContent.isHidden = !mHudVisible
            infoLabel.isHidden = !mHudVisible
            actionNewScanEnabled = true
            actionNewDataRecording = true
            actionSaveEnabled = mMapNodes>0
            actionResumeEnabled = mMapNodes>0
            actionExportEnabled = mMapNodes>0
            actionOptimizeEnabled = mMapNodes>0
            actionSettingsEnabled = true
            cropButton.isHidden = true
            cancelButton.isHidden = true
            editsaveButton.isHidden = true
        case .STATE_IDLE: // IDLE
            projectButton.isHidden = !mHudVisible
            libraryButton.isHidden = mState != .STATE_WELCOME && !mHudVisible
            menuButton.isHidden = mState != .STATE_WELCOME && !mHudVisible
            viewButton.isHidden = mState != .STATE_WELCOME && !mHudVisible
            startButton.isHidden = !mHudVisible
            recordButton.isHidden = true
            stopButton.isHidden = true
            saveButton.isHidden = true
            editButton.isHidden = !mHudVisible
            mapButton.isHidden = !mHudVisible
            closeVisualizationButton.isHidden = true
            stopCameraButton.isHidden = true
//            orthoDistanceSlider.isHidden = true
//            orthoGridSlider.isHidden = true
            titleContent.isHidden = !mHudVisible
            infoLabel.isHidden = !mHudVisible
            actionNewScanEnabled = true
            actionNewDataRecording = true
            actionSaveEnabled = mState != .STATE_WELCOME && mMapNodes>0
            actionResumeEnabled = mState != .STATE_WELCOME && mMapNodes>0
            actionExportEnabled = mState != .STATE_WELCOME && mMapNodes>0
            actionOptimizeEnabled = mState != .STATE_WELCOME && mMapNodes>0
            actionSettingsEnabled = true
            cropButton.isHidden = true
            cancelButton.isHidden = true
            editsaveButton.isHidden = true
        case .STATE_EDIT: // EDIT
            projectButton.isHidden = true
            libraryButton.isHidden = true
            menuButton.isHidden = true
            viewButton.isHidden = false
            startButton.isHidden = true
            recordButton.isHidden = true
            stopButton.isHidden = true
            saveButton.isHidden = true
            editButton.isHidden = false
            mapButton.isHidden = true
            closeVisualizationButton.isHidden = true
            stopCameraButton.isHidden = true
//            orthoDistanceSlider.isHidden = true
//            orthoGridSlider.isHidden = true
            titleContent.isHidden = false
            infoLabel.isHidden = false
            actionNewScanEnabled = true
            actionNewDataRecording = true
            actionSaveEnabled = mMapNodes>0
            actionResumeEnabled = mMapNodes>0
            actionExportEnabled = mMapNodes>0
            actionOptimizeEnabled = mMapNodes>0
            actionSettingsEnabled = true
            cropButton.isHidden = false
            cancelButton.isHidden = false
            editsaveButton.isHidden = false
            if isCropping {
                editsaveButton.isEnabled = false
            } else {
                editsaveButton.isEnabled = true
            }
        default: // Welcome
            projectButton.isHidden = mState != .STATE_WELCOME
            libraryButton.isHidden = mState != .STATE_WELCOME
            menuButton.isHidden = mState != .STATE_WELCOME
            viewButton.isHidden = true
            startButton.isHidden = false
//            startButton.isHidden = selectedProjectFolderURL == nil
            recordButton.isHidden = true
            stopButton.isHidden = true
            saveButton.isHidden = true
            editButton.isHidden = true
            mapButton.isHidden = false
            closeVisualizationButton.isHidden = true
            stopCameraButton.isHidden = true
            infoLabel.isHidden = true
            titleContent.isHidden = true
//            orthoDistanceSlider.isHidden = true
//            orthoGridSlider.isHidden = true
            actionNewScanEnabled = true
            actionSaveEnabled = mState != .STATE_WELCOME && mMapNodes>0
            actionResumeEnabled = mState != .STATE_WELCOME && mMapNodes>0
            actionExportEnabled = mState != .STATE_WELCOME && mMapNodes>0
            actionOptimizeEnabled = mState != .STATE_WELCOME && mMapNodes>0
            actionSettingsEnabled = true
            cropButton.isHidden = true
            cancelButton.isHidden = true
            editsaveButton.isHidden = true
        }

        let view = self.view as? GLKView
        if(mState != .STATE_MAPPING && mState != .STATE_CAMERA && mState != .STATE_VISUALIZING_CAMERA)
        {
            self.isPaused = true
            view?.enableSetNeedsDisplay = true
            self.view.setNeedsDisplay()
            print("enableSetNeedsDisplay")
        }
        else
        {
            view?.enableSetNeedsDisplay = false
            self.isPaused = false
            print("diaableSetNeedsDisplay")
        }
        
        if !self.isPaused {
            self.view.setNeedsDisplay()
        }
        // PointCloud menu
        let pointCloudMenu = UIMenu(title: "Point cloud...", children: [
            UIAction(title: "Current Density", handler: { _ in
                self.export(isOBJ: false, meshing: false, regenerateCloud: false, optimized: false, optimizedMaxPolygons: 0, previousState: self.mState)
            }),
            UIAction(title: "Max Density", handler: { _ in
                self.export(isOBJ: false, meshing: false, regenerateCloud: true, optimized: false, optimizedMaxPolygons: 0, previousState: self.mState)
            })
        ])
        // Optimized Mesh menu
        let optimizedMeshMenu = UIMenu(title: "Optimized mesh...", children: [
            UIAction(title: "Colored Mesh", handler: { _ in
                self.exportMesh(isOBJ: false)
            }),
            UIAction(title: "Textured Mesh", handler: { _ in
                self.exportMesh(isOBJ: true)
            })
        ])
        
        // Export menu
        let exportMenu = UIMenu(title: "Assemble...", children: [pointCloudMenu, optimizedMeshMenu])
        
        // Optimized Mesh menu
        let optimizeAdvancedMenu = UIMenu(title: "Advanced...", children: [
            UIAction(title: "Global Graph Optimization", handler: { _ in
                self.optimization(approach: 0)
            }),
            UIAction(title: "Detect More Loop Closures", handler: { _ in
                self.optimization(approach: 2)
            }),
            UIAction(title: "Adjust Colors (Fast)", handler: { _ in
                self.optimization(approach: 5)
            }),
            UIAction(title: "Adjust Colors (Full)", handler: { _ in
                self.optimization(approach: 6)
            }),
            UIAction(title: "Mesh Smoothing", handler: { _ in
                self.optimization(approach: 7)
            }),
            UIAction(title: "Bundle Adjustment", handler: { _ in
                self.optimization(approach: 1)
            }),
            UIAction(title: "Noise Filtering", handler: { _ in
                self.optimization(approach: 4)
            }),
            UIAction(title: "Clipping", handler: { _ in
                self.optimization(approach: 8)
            })
        ])
        
        // Optimize menu
        let optimizeMenu = UIMenu(title: "Optimize...", children: [
            UIAction(title: "Standard Optimization", handler: { _ in
                self.optimization(approach: -1)
            }),
            optimizeAdvancedMenu])

        var fileMenuChildren: [UIMenuElement] = []
        fileMenuChildren.append(UIAction(title: "New Mapping Session", image: UIImage(systemName: "plus.app"), attributes: actionNewScanEnabled ? [] : .disabled, state: .off, handler: { _ in
            self.newScan()
        }))
        fileMenuChildren.append(UIAction(title: "Save", image: UIImage(systemName: "square.and.arrow.down"), attributes: actionSaveEnabled ? [] : .disabled, state: .off, handler: { _ in
            self.save()
        }))
        
        if(actionOptimizeEnabled) {
            fileMenuChildren.append(optimizeMenu)
        }
        else {
            fileMenuChildren.append(UIAction(title: "Optimize...", attributes: .disabled, state: .off, handler: { _ in
            }))
        }
        if(actionExportEnabled) {
            fileMenuChildren.append(exportMenu)
        }
        else {
            fileMenuChildren.append(UIAction(title: "Assemble...", attributes: .disabled, state: .off, handler: { _ in
            }))
        }
        
        //MARK: UI - File menu Tab
        let fileMenu = UIMenu(title: "File", options: .displayInline, children: fileMenuChildren)
        
        let settingsMenu = UIMenu(title: "Settings", options: .displayInline, children: [
            UIAction(title: "Settings", image: UIImage(systemName: "gearshape.2"), attributes: actionSettingsEnabled ? [] : .disabled, state: .off, handler: { _ in
                guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
                    return
                }

                if UIApplication.shared.canOpenURL(settingsUrl) {
                    UIApplication.shared.open(settingsUrl, completionHandler: { (success) in
                        print("Settings opened: \(success)") // Prints true
                    })
                }
            }),
            UIAction(title: "Restore All Default Settings", attributes: actionSettingsEnabled ? [] : .disabled, state: .off, handler: { _ in
                
                let ac = UIAlertController(title: "Reset All Default Settings", message: "Do you want to reset all settings to default?", preferredStyle: .alert)
                ac.addAction(UIAlertAction(title: "Yes", style: .default, handler: { _ in
                    let notificationCenter = NotificationCenter.default
                    notificationCenter.removeObserver(self)
                    UserDefaults.standard.reset()
                    self.registerSettingsBundle()
                    self.updateDisplayFromDefaults();
                    notificationCenter.addObserver(self, selector: #selector(self.defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
                }))
                ac.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil))
                self.present(ac, animated: true)
             })
        ])

        menuButton.menu = UIMenu(title: "", children: [fileMenu, settingsMenu])
        menuButton.addTarget(self, action: #selector(ViewController.menuOpened(_:)), for: .menuActionTriggered)
        
        let cameraMenu = UIMenu(title: "View", options: .displayInline, children: [
            UIAction(title: "Third-P. View", image: cameraMode == 1 ? UIImage(systemName: "checkmark.circle") : UIImage(systemName: "circle"), handler: { _ in
                self.setGLCamera(type: 1)
                self.TouchAction(true)
            }),
            UIAction(title: "Top View", image: cameraMode == 2 ? UIImage(systemName: "checkmark.circle") : UIImage(systemName: "circle"), handler: { _ in
                self.setGLCamera(type: 2)
                self.TouchAction(true)
            }),
            UIAction(title: "Ortho View", image: cameraMode == 3 ? UIImage(systemName: "checkmark.circle") : UIImage(systemName: "circle"), handler: { _ in
                self.setGLCamera(type: 3)
                self.TouchAction(true)
            }),
            UIAction(title: "First-P. View", image: cameraMode == 0 ? UIImage(systemName: "checkmark.circle") : UIImage(systemName: "circle"), attributes: (self.mState == .STATE_CAMERA || self.mState == .STATE_MAPPING || self.mState == .STATE_VISUALIZING_CAMERA) ? [] : .disabled, handler: { _ in
                self.setGLCamera(type: 0)
                if(self.mState == .STATE_VISUALIZING)
                {
                    self.rtabmap?.setLocalizationMode(enabled: true)
                    self.rtabmap?.setPausedMapping(paused: false);
                    self.startCamera()
                    self.updateState(state: .STATE_VISUALIZING_CAMERA)
                }
                else
                {
                    self.resetNoTouchTimer(true)
                }
            })
        ])

        let DebugMenu = UIMenu(title: "Debug", options: .displayInline, children: [
            UIAction(title: "Debug", image: debugShown ? UIImage(systemName: "checkmark.circle") : UIImage(systemName: "circle"), attributes: (self.mState != .STATE_WELCOME) ? [] : .disabled, handler: { _ in
                self.debugShown = !self.debugShown
                self.statusShown = !self.statusShown
                self.TouchAction(true)
            })
        ])

        var viewMenuChildren: [UIMenuElement] = []
        viewMenuChildren.append(DebugMenu)
        viewMenuChildren.append(cameraMenu)
        viewButton.menu = UIMenu(title: "", children: viewMenuChildren)
        viewButton.addTarget(self, action: #selector(ViewController.menuOpened(_:)), for: .menuActionTriggered)
    }
    
    @IBAction func menuOpened(_ sender:UIButton)
    {
        mMenuOpened = true;
    }
    
    func exportMesh(isOBJ: Bool)
    {
        let ac = UIAlertController(title: "Maximum Polygons", message: "\n\n\n\n\n\n\n\n\n\n", preferredStyle: .alert)
        ac.view.addSubview(maxPolygonsPickerView)
        maxPolygonsPickerView.selectRow(2, inComponent: 0, animated: false)
        ac.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            let pickerValue = self.maxPolygonsPickerData[self.maxPolygonsPickerView.selectedRow(inComponent: 0)]
            self.export(isOBJ: isOBJ, meshing: true, regenerateCloud: false, optimized: true, optimizedMaxPolygons: pickerValue*100000, previousState: self.mState);
        }))
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(ac, animated: true)
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return maxPolygonsPickerData.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if(row == 0)
        {
            return "No Limit"
        }
        return "\(maxPolygonsPickerData[row])00 000"
    }
    
    // Auto-hide the home indicator to maximize immersion in AR experiences.
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    // Hide the status bar to maximize immersion in AR experiences.
    override var prefersStatusBarHidden: Bool {
        return !mHudVisible
    }

    //This is called when a new frame has been updated.
    func session(_ session: ARSession, didUpdate frame: ARFrame)
    {
        var status = ""
        var accept = false
        
        switch frame.camera.trackingState {
        case .normal:
            accept = true
        case .notAvailable:
            status = "Tracking not available"
        case .limited(.excessiveMotion):
            accept = true
            status = "Please Slow Your Movement"
        case .limited(.insufficientFeatures):
            accept = true
            status = "Avoid Featureless Surfaces"
        case .limited(.initializing):
            status = "Initializing"
        case .limited(.relocalizing):
            status = "Relocalizing"
        default:
            status = "Unknown tracking state"
        }
        
        mLastLightEstimate = frame.lightEstimate?.ambientIntensity
        
        if !status.isEmpty && mLastLightEstimate != nil && mLastLightEstimate! < 100 && accept {
            status = "Camera Is Occluded Or Lighting Is Too Dark"
        }

        if let rotation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation
        {
            rtabmap?.postOdometryEvent(frame: frame, orientation: rotation, viewport: self.view.frame.size)
        }
        
        if !status.isEmpty {
            DispatchQueue.main.async {
                self.showToast(message: status, seconds: 3)
            }
        }
    }
    
    // This is called when a session fails.
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user.
        guard error is ARError else { return }
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                if let configuration = self.session.configuration {
                    self.session.run(configuration, options: [.resetSceneReconstruction, .resetTracking, .removeExistingAnchors])
                }
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
    {
        mLastKnownLocation = locations.last!
        rtabmap?.setGPS(location: locations.last!);
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
    {
        print(error)
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus)
    {
        print(status.rawValue)
        if(status == .notDetermined)
        {
            locationManager?.requestWhenInUseAuthorization()
        }
        if(status == .denied)
        {
            let alertController = UIAlertController(title: "GPS Disabled", message: "GPS option is enabled (Settings->Mapping...) but localization is denied for this App. To enable location for this App, go in Settings->Privacy->Location.", preferredStyle: .alert)

            let settingsAction = UIAlertAction(title: "Settings", style: .default) { (action) in
                self.locationManager = nil
                self.mLastKnownLocation = nil
                guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
                    return
                }

                if UIApplication.shared.canOpenURL(settingsUrl) {
                    UIApplication.shared.open(settingsUrl, completionHandler: { (success) in
                        print("Settings opened: \(success)") // Prints true
                    })
                }
            }
            alertController.addAction(settingsAction)
            
            let okAction = UIAlertAction(title: "Turn Off GPS", style: .default) { (action) in
                UserDefaults.standard.setValue(false, forKey: "SaveGPS")
                self.updateDisplayFromDefaults()
            }
            alertController.addAction(okAction)
            
            present(alertController, animated: true)
        }
        else if(status == .authorizedWhenInUse)
        {
            if locationManager != nil {
                if(locationManager!.accuracyAuthorization == .reducedAccuracy) {
                    let alertController = UIAlertController(title: "GPS Reduced Accuracy", message: "Your location settings for this App is set to reduced accuracy. We recommend to use high accuracy.", preferredStyle: .alert)

                    let settingsAction = UIAlertAction(title: "Settings", style: .default) { (action) in
                        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
                            return
                        }

                        if UIApplication.shared.canOpenURL(settingsUrl) {
                            UIApplication.shared.open(settingsUrl, completionHandler: { (success) in
                                print("Settings opened: \(success)") // Prints true
                            })
                        }
                    }
                    alertController.addAction(settingsAction)
                    
                    let okAction = UIAlertAction(title: "Ignore", style: .default) { (action) in
                    }
                    alertController.addAction(okAction)
                    
                    present(alertController, animated: true)
                }
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // The screen shouldn't dim during AR experiences.
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    var statusBarOrientation: UIInterfaceOrientation? {
        get {
            guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else {
                #if DEBUG
                fatalError("Could not obtain UIInterfaceOrientation from a valid windowScene")
                #else
                return nil
                #endif
            }
            return orientation
        }
    }
        
    deinit {
        EAGLContext.setCurrent(context)
        rtabmap = nil
        context = nil
        EAGLContext.setCurrent(nil)
    }
    
    var firstTouch: UITouch?
    var secondTouch: UITouch?
    
    override func touchesBegan(_ touches: Set<UITouch>,
                 with event: UIEvent?)
    {
        super.touchesBegan(touches, with: event)
        for touch in touches {
            if (firstTouch == nil) {
                firstTouch = touch
                let pose = touch.location(in: self.view)
                let normalizedX = pose.x / self.view.bounds.size.width;
                let normalizedY = pose.y / self.view.bounds.size.height;
                rtabmap?.onTouchEvent(touch_count: 1, event: 0, x0: Float(normalizedX), y0: Float(normalizedY), x1: 0.0, y1: 0.0);
            }
            else if (firstTouch != nil && secondTouch == nil)
            {
                secondTouch = touch
                if let pose0 = firstTouch?.location(in: self.view)
                {
                    if let pose1 = secondTouch?.location(in: self.view)
                    {
                        let normalizedX0 = pose0.x / self.view.bounds.size.width;
                        let normalizedY0 = pose0.y / self.view.bounds.size.height;
                        let normalizedX1 = pose1.x / self.view.bounds.size.width;
                        let normalizedY1 = pose1.y / self.view.bounds.size.height;
                        rtabmap?.onTouchEvent(touch_count: 2, event: 5, x0: Float(normalizedX0), y0: Float(normalizedY0), x1: Float(normalizedX1), y1: Float(normalizedY1));
                    }
                }
            }
        }
        if self.isPaused {
            self.view.setNeedsDisplay()
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        var firstTouchUsed = false
        var secondTouchUsed = false
        for touch in touches {
            if(touch == firstTouch)
            {
                firstTouchUsed = true
            }
            else if(touch == secondTouch)
            {
                secondTouchUsed = true
            }
        }
        if(secondTouch != nil)
        {
            if(firstTouchUsed || secondTouchUsed)
            {
                if let pose0 = firstTouch?.location(in: self.view)
                {
                    if let pose1 = secondTouch?.location(in: self.view)
                    {
                        let normalizedX0 = pose0.x / self.view.bounds.size.width;
                        let normalizedY0 = pose0.y / self.view.bounds.size.height;
                        let normalizedX1 = pose1.x / self.view.bounds.size.width;
                        let normalizedY1 = pose1.y / self.view.bounds.size.height;
                        rtabmap?.onTouchEvent(touch_count: 2, event: 2, x0: Float(normalizedX0), y0: Float(normalizedY0), x1: Float(normalizedX1), y1: Float(normalizedY1));
                    }
                }
            }
        }
        else if(firstTouchUsed)
        {
            if let pose = firstTouch?.location(in: self.view)
            {
                let normalizedX = pose.x / self.view.bounds.size.width;
                let normalizedY = pose.y / self.view.bounds.size.height;
                rtabmap?.onTouchEvent(touch_count: 1, event: 2, x0: Float(normalizedX), y0: Float(normalizedY), x1: 0.0, y1: 0.0);
            }
        }
        if self.isPaused {
            self.view.setNeedsDisplay()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        for touch in touches {
            if(touch == firstTouch)
            {
                firstTouch = nil
            }
            else if(touch == secondTouch)
            {
                secondTouch = nil
            }
        }
        if (firstTouch == nil && secondTouch != nil)
        {
            firstTouch = secondTouch
            secondTouch = nil
        }
        if (firstTouch != nil && secondTouch == nil)
        {
            let pose = firstTouch!.location(in: self.view)
            let normalizedX = pose.x / self.view.bounds.size.width;
            let normalizedY = pose.y / self.view.bounds.size.height;
            rtabmap?.onTouchEvent(touch_count: 1, event: 0, x0: Float(normalizedX), y0: Float(normalizedY), x1: 0.0, y1: 0.0);
        }
        if self.isPaused {
            self.view.setNeedsDisplay()
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        for touch in touches {
            if(touch == firstTouch)
            {
                firstTouch = nil;
            }
            else if(touch == secondTouch)
            {
                secondTouch = nil;
            }
        }
        if self.isPaused {
            self.view.setNeedsDisplay()
        }
    }
    
    //MARK: TouchAction
    @IBAction func doubleTapped(_ gestureRecognizer: UITapGestureRecognizer) {
        if gestureRecognizer.state == UIGestureRecognizer.State.recognized
        {
            let pose = gestureRecognizer.location(in: gestureRecognizer.view)
            let normalizedX = pose.x / self.view.bounds.size.width;
            let normalizedY = pose.y / self.view.bounds.size.height;
            
            if isCropping != true {
                rtabmap?.onTouchEvent(touch_count: 3, event: 0, x0: Float(normalizedX), y0: Float(normalizedY), x1: 0.0, y1: 0.0);
                print("doubleTapped")
            }
            if self.isPaused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.view.setNeedsDisplay()
                }
            }
        }
    }
    
    @IBAction func singleTapped(_ gestureRecognizer: UITapGestureRecognizer) {
        if gestureRecognizer.state == .recognized
        {
            let pose = gestureRecognizer.location(in: gestureRecognizer.view)
            let normalizedX = pose.x / self.view.bounds.size.width
            let normalizedY = pose.y / self.view.bounds.size.height
            
            if isCropping {
                print("singleTapped & Cropping")
                rtabmap?.onTouchEvent(touch_count: 3, event: 7, x0: Float(normalizedX), y0: Float(normalizedY), x1: 0.0, y1: 0.0);
                
                if self.isPaused {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.view.setNeedsDisplay()
                    }
                }
            }
            else{
                TouchAction(!mHudVisible)
                rtabmap?.onTouchEvent(touch_count: 1, event: 7, x0: Float(normalizedX), y0: Float(normalizedY), x1: 0.0, y1: 0.0)
                print("singleTapped")
                if self.isPaused {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.view.setNeedsDisplay()
                    }
                }
            }

        }
    }
    
    func registerSettingsBundle(){
        let appDefaults = [String:AnyObject]()
        UserDefaults.standard.register(defaults: appDefaults)
    }
    
    func updateDisplayFromDefaults()
    {
        //Get the defaults
        let defaults = UserDefaults.standard
 
        //let appendMode = defaults.bool(forKey: "AppendMode")
        
        // update preference
        rtabmap!.setOnlineBlending(enabled: defaults.bool(forKey: "Blending"));
        rtabmap!.setNodesFiltering(enabled: defaults.bool(forKey: "NodesFiltering"));
        rtabmap!.setFullResolution(enabled: defaults.bool(forKey: "HDMode"));
        rtabmap!.setSmoothing(enabled: defaults.bool(forKey: "Smoothing"));
        rtabmap!.setAppendMode(enabled: defaults.bool(forKey: "AppendMode"));
        rtabmap!.setUpstreamRelocalizationAccThr(value: defaults.float(forKey: "UpstreamRelocalizationFilteringAccThr"));
//        rtabmap!.setExportPointCloudFormat(format: defaults.string(forKey: "ExportPointCloudFormat")!);
        
        mTimeThr = (defaults.string(forKey: "TimeLimit")! as NSString).integerValue
        mMaxFeatures = (defaults.string(forKey: "MaxFeaturesExtractedLoopClosure")! as NSString).integerValue
        
        // Mapping parameters
        rtabmap!.setMappingParameter(key: "Rtabmap/DetectionRate", value: defaults.string(forKey: "UpdateRate")!);
        rtabmap!.setMappingParameter(key: "Rtabmap/TimeThr", value: defaults.string(forKey: "TimeLimit")!);
        rtabmap!.setMappingParameter(key: "Rtabmap/MemoryThr", value: defaults.string(forKey: "MemoryLimit")!);
        rtabmap!.setMappingParameter(key: "RGBD/LinearSpeedUpdate", value: defaults.string(forKey: "MaximumMotionSpeed")!);
        let motionSpeed = ((defaults.string(forKey: "MaximumMotionSpeed")!) as NSString).floatValue/2.0;
        rtabmap!.setMappingParameter(key: "RGBD/AngularSpeedUpdate", value: NSString(format: "%.2f", motionSpeed) as String);
        rtabmap!.setMappingParameter(key: "Rtabmap/LoopThr", value: defaults.string(forKey: "LoopClosureThreshold")!);
        rtabmap!.setMappingParameter(key: "Mem/RehearsalSimilarity", value: defaults.string(forKey: "SimilarityThreshold")!);
        rtabmap!.setMappingParameter(key: "Kp/MaxFeatures", value: defaults.string(forKey: "MaxFeaturesExtractedVocabulary")!);
        rtabmap!.setMappingParameter(key: "Vis/MaxFeatures", value: defaults.string(forKey: "MaxFeaturesExtractedLoopClosure")!);
        rtabmap!.setMappingParameter(key: "Vis/MinInliers", value: defaults.string(forKey: "MinInliers")!);
        rtabmap!.setMappingParameter(key: "RGBD/OptimizeMaxError", value: defaults.string(forKey: "MaxOptimizationError")!);
        rtabmap!.setMappingParameter(key: "Kp/DetectorStrategy", value: defaults.string(forKey: "FeatureType")!);
        rtabmap!.setMappingParameter(key: "Vis/FeatureType", value: defaults.string(forKey: "FeatureType")!);
        rtabmap!.setMappingParameter(key: "Mem/NotLinkedNodesKept", value: defaults.bool(forKey: "SaveAllFramesInDatabase") ? "true" : "false");
        rtabmap!.setMappingParameter(key: "RGBD/OptimizeFromGraphEnd", value: defaults.bool(forKey: "OptimizationfromGraphEnd") ? "true" : "false");
        rtabmap!.setMappingParameter(key: "RGBD/MaxOdomCacheSize", value: defaults.string(forKey: "MaximumOdometryCacheSize")!);
        rtabmap!.setMappingParameter(key: "Optimizer/Strategy", value: defaults.string(forKey: "GraphOptimizer")!);
        rtabmap!.setMappingParameter(key: "RGBD/ProximityBySpace", value: defaults.string(forKey: "ProximityDetection")!);

        let markerDetection = defaults.integer(forKey: "ArUcoMarkerDetection")
        if(markerDetection == -1)
        {
            rtabmap!.setMappingParameter(key: "RGBD/MarkerDetection", value: "false");
        }
        else
        {
            rtabmap!.setMappingParameter(key: "RGBD/MarkerDetection", value: "true");
            rtabmap!.setMappingParameter(key: "Marker/Dictionary", value: defaults.string(forKey: "ArUcoMarkerDetection")!);
            rtabmap!.setMappingParameter(key: "Marker/CornerRefinementMethod", value: (markerDetection > 16 ? "3":"0"));
            rtabmap!.setMappingParameter(key: "Marker/MaxDepthError", value: defaults.string(forKey: "MarkerDepthErrorEstimation")!);
            if let val = NumberFormatter().number(from: defaults.string(forKey: "MarkerSize")!)?.doubleValue
            {
                rtabmap!.setMappingParameter(key: "Marker/Length", value: String(format: "%f", val/100.0))
            }
            else{
                rtabmap!.setMappingParameter(key: "Marker/Length", value: "0")
            }
        }

        // Rendering
        rtabmap!.setCloudDensityLevel(value: defaults.integer(forKey: "PointCloudDensity"));
        rtabmap!.setMaxCloudDepth(value: defaults.float(forKey: "MaxDepth"));
        rtabmap!.setMinCloudDepth(value: defaults.float(forKey: "MinDepth"));
        rtabmap!.setDepthConfidence(value: defaults.integer(forKey: "DepthConfidence"));
        rtabmap!.setPointSize(value: defaults.float(forKey: "PointSize"));
        rtabmap!.setMeshAngleTolerance(value: defaults.float(forKey: "MeshAngleTolerance"));
        rtabmap!.setMeshTriangleSize(value: defaults.integer(forKey: "MeshTriangleSize"));
        rtabmap!.setMeshDecimationFactor(value: defaults.float(forKey: "MeshDecimationFactor"));
        let bgColor = defaults.float(forKey: "BackgroundColor");
        rtabmap!.setBackgroundColor(gray: bgColor);
//        let format = defaults.string(forKey: "ExportPointCloudFormat")!;
        DispatchQueue.main.async {
            self.statusLabel.textColor = bgColor>=0.6 ? UIColor(white: 0.0, alpha: 1) : UIColor(white: 1.0, alpha: 1)
//            self.exportOBJPLYButton.setTitle("Export OBJ-\(format == "las" ? "LAS" : "PLY")", for: .normal)
        }
    
        rtabmap!.setClusterRatio(value: defaults.float(forKey: "NoiseFilteringRatio"));
        rtabmap!.setMaxGainRadius(value: defaults.float(forKey: "ColorCorrectionRadius"));
        rtabmap!.setRenderingTextureDecimation(value: defaults.integer(forKey: "TextureResolution"));
        
        if(locationManager != nil && !defaults.bool(forKey: "SaveGPS"))
        {
            locationManager?.stopUpdatingLocation()
            locationManager = nil
            mLastKnownLocation = nil
        }
        else if(locationManager == nil && defaults.bool(forKey: "SaveGPS"))
        {
            locationManager = CLLocationManager()
            locationManager?.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager?.delegate = self
        }
    }
    
    func resumeScan()
    {
        if(mState == State.STATE_VISUALIZING)
        {
            closeVisualization()
            rtabmap!.postExportation(visualize: false)
        }
        
        if(!mDataRecording) {
            let alertController = UIAlertController(title: "Append Mode", message: "The camera preview will not be aligned to map on start, move to a previously scanned area, then push Record. When a loop closure is detected, new scans will be appended to map.", preferredStyle: .alert)

            let okAction = UIAlertAction(title: "OK", style: .default) { (action) in
            }
            alertController.addAction(okAction)

            present(alertController, animated: true)
        }
        
        setGLCamera(type: 0);
        startCamera();
    }
    
    //MARK: NEW SCAN
    func newScan(dataRecordingMode: Bool = false)
    {
        print("databases.size() = \(databases.size())")
        if(mState == State.STATE_WELCOME)
        {
            viewMode = 0
        }
        if(mState == State.STATE_VISUALIZING)
        {
            closeVisualization()
        }
        if(mState == State.STATE_EDIT)
        {
            closeVisualization()
        }

        mMapNodes = 0;

        self.openedDatabasePath = nil
        let tmpDatabase = self.getDocumentDirectory().appendingPathComponent(self.RTABMAP_TMP_DB)
        let inMemory = UserDefaults.standard.bool(forKey: "DatabaseInMemory")
        if(!(self.mState == State.STATE_CAMERA || self.mState == State.STATE_MAPPING) &&
           FileManager.default.fileExists(atPath: tmpDatabase.path) &&
           tmpDatabase.fileSize > 1024*1024) // > 1MB
        {
            dismiss(animated: true, completion: {
                let msg = "The previous session (\(tmpDatabase.fileSizeString)) was not correctly saved, do you want to recover it?"
                let alert = UIAlertController(title: "Recovery", message: msg, preferredStyle: .alert)
                let alertActionNo = UIAlertAction(title: "Ignore", style: .destructive) {
                    (UIAlertAction) -> Void in
                    do {
                        try FileManager.default.removeItem(at: tmpDatabase)
                    }
                    catch {
                        print("Could not clear tmp database: \(error)")
                    }
                    self.newScan(dataRecordingMode: dataRecordingMode)
                }
                alert.addAction(alertActionNo)
                let alertActionCancel = UIAlertAction(title: "Cancel", style: .cancel) {
                    (UIAlertAction) -> Void in
                    // do nothing
                }
                alert.addAction(alertActionCancel)
                let alertActionYes = UIAlertAction(title: "Yes", style: .default) {
                    (UIAlertAction2) -> Void in

                    let fileName = Date().getFormattedDate(format: "yyMMdd-HHmmss") + ".db"
                    let outputDbPath = self.getDocumentDirectory().appendingPathComponent(fileName).path
                    
                    var indicator: UIActivityIndicatorView?
                    
                    let alertView = UIAlertController(title: "Recovering", message: "Please wait while recovering data...", preferredStyle: .alert)
                    let alertViewActionCancel = UIAlertAction(title: "Cancel", style: .cancel) {
                        (UIAlertAction) -> Void in
                        self.dismiss(animated: true, completion: {
                            self.progressView = nil
                            
                            indicator = UIActivityIndicatorView(style: .large)
                            indicator?.frame = CGRect(x: 0.0, y: 0.0, width: 60.0, height: 60.0)
                            indicator?.center = self.view.center
                            self.view.addSubview(indicator!)
                            indicator?.bringSubviewToFront(self.view)
                            
                            indicator?.startAnimating()
                            self.rtabmap!.cancelProcessing();
                        })
                    }
                    alertView.addAction(alertViewActionCancel)
                    
                    let previousState = self.mState
                    self.updateState(state: .STATE_PROCESSING);
                    
                    self.present(alertView, animated: true, completion: {
                        //  Add your progressbar after alert is shown (and measured)
                        let margin:CGFloat = 8.0
                        let rect = CGRect(x: margin, y: 84.0, width: alertView.view.frame.width - margin * 2.0 , height: 2.0)
                        self.progressView = UIProgressView(frame: rect)
                        self.progressView!.progress = 0
                        self.progressView!.tintColor = self.view.tintColor
                        alertView.view.addSubview(self.progressView!)
                        
                        var success : Bool = false
                        DispatchQueue.background(background: {
                            
                            success = self.rtabmap!.recover(from: tmpDatabase.path, to: outputDbPath)
                            
                        }, completion:{
                            if(indicator != nil)
                            {
                                indicator!.stopAnimating()
                                indicator!.removeFromSuperview()
                            }
                            if self.progressView != nil
                            {
                                self.dismiss(animated: self.openedDatabasePath == nil, completion: {
                                    if(success)
                                    {
                                        let alertSaved = UIAlertController(title: "Database saved.", message: String(format: "Database \"%@\" successfully recovered.", fileName), preferredStyle: .alert)
                                        let yes = UIAlertAction(title: "OK", style: .default) {
                                            (UIAlertAction) -> Void in
                                            self.openDatabase(fileUrl: URL(fileURLWithPath: outputDbPath))
                                        }
                                        alertSaved.addAction(yes)
                                        self.present(alertSaved, animated: true, completion: nil)
                                    }
                                    else
                                    {
                                        self.updateState(state: previousState);
                                        self.showToast(message: "Recovery failed.", seconds: 4)
                                    }
                                })
                            }
                            else
                            {
                                self.showToast(message: "Recovery canceled", seconds: 2)
                                self.updateState(state: previousState);
                            }
                        })
                    })
                }
                alert.addAction(alertActionYes)
                self.present(alert, animated: true, completion: nil)
            })
        }
        else
        {
            let inMemory = UserDefaults.standard.bool(forKey: "DatabaseInMemory") && !dataRecordingMode
            mDataRecording = dataRecordingMode
            self.rtabmap!.setDataRecorderMode(enabled: dataRecordingMode)
            self.optimizedGraphShown = true // Always reset to true when opening a database
            self.rtabmap!.openDatabase(databasePath: tmpDatabase.path, databaseInMemory: inMemory, optimize: false, clearDatabase: true)

            if(!(self.mState == State.STATE_CAMERA || self.mState == State.STATE_MAPPING))
            {
                if(mDataRecording) {
                    let alertController = UIAlertController(title: "Data Recording Mode", message: "This mode should be only used if you want to record raw ARKit data as long as possible without any feedback: loop closure detection and map rendering are disabled. The database size in Debug display shows how much data has been recorded so far.", preferredStyle: .alert)

                    let okAction = UIAlertAction(title: "OK", style: .default) { (action) in
                    }
                    alertController.addAction(okAction)

                    present(alertController, animated: true)
                    self.debugShown = false
                }
                self.setGLCamera(type: 0);
                self.startCamera();
            }
        }
    }
    
    //MARK: SAVE Function (팝업)
    func save()
    {
        //Step : 1
        let alert = UIAlertController(title: "Save Scan", message: "Database Name (*.db):", preferredStyle: .alert )
        //Step : 2
        let save = UIAlertAction(title: "Save", style: .default) { (alertAction) in
            let textField = alert.textFields![0] as UITextField
            if textField.text != "" {
                //Read TextFields text data
                let fileName = textField.text!+".db"
                let filePath = self.getDocumentDirectory().appendingPathComponent(fileName).path
                if FileManager.default.fileExists(atPath: filePath) {
                    let alert = UIAlertController(title: "File Already Exists", message: "Do you want to overwrite the existing file?", preferredStyle: .alert)
                    let yes = UIAlertAction(title: "Yes", style: .default) {
                        (UIAlertAction) -> Void in
                        self.saveDatabase(fileName: fileName);
                    }
                    alert.addAction(yes)
                    let no = UIAlertAction(title: "No", style: .cancel) {
                        (UIAlertAction) -> Void in
                        if(self.mDataRecording) {
                            self.save() // We cannot skip saving after data recording
                        }
                    }
                    alert.addAction(no)
                    
                    self.present(alert, animated: true, completion: nil)
                } else {
                    self.saveDatabase(fileName: fileName);
                }
            }
            else
            {
                self.save()
            }
        }

        //Step : 3
        var placeholder = Date().getFormattedDate(format: "yyMMdd_HHmmss")
        if(mDataRecording) {
            placeholder += "-recording"
        }
        if self.openedDatabasePath != nil && !self.openedDatabasePath!.path.isEmpty
        {
            var components = self.openedDatabasePath!.lastPathComponent.components(separatedBy: ".")
            if components.count > 1 { // If there is a file extension
                components.removeLast()
                placeholder = components.joined(separator: ".")
            } else {
                placeholder = self.openedDatabasePath!.lastPathComponent
            }
        }
        alert.addTextField { (textField) in
                textField.text = placeholder
        }

        //Step : 4
        alert.addAction(save)
        //Cancel action
        if(!mDataRecording) {
            alert.addAction(UIAlertAction(title: "Cancel", style: .default) { (alertAction) in })
        }

        self.present(alert, animated: true) {
            alert.textFields?.first?.selectAll(nil)
        }
    }
    
    // MARK: - CSV Handling

    func saveCSV(fileName: String) {
        guard let location = self.mLastKnownLocation else {
            print("No location data available to save.")
            return
        }
        
        let csvFileName = (fileName as NSString).deletingPathExtension + ".csv"
        let csvFileURL = self.getDocumentDirectory().appendingPathComponent(csvFileName)
        
        let project = self.getDocumentDirectory().lastPathComponent
        let name = (fileName as NSString).deletingPathExtension
        let longitude = location.coordinate.longitude
        let latitude = location.coordinate.latitude
        let altitude = location.altitude
        let volume = 0.0 // Initial volume
        
        if FileManager.default.fileExists(atPath: csvFileURL.path) {
            // CSV exists, check if record exists
            do {
                var csvContent = try String(contentsOf: csvFileURL, encoding: .utf8)
                var lines = csvContent.components(separatedBy: .newlines)
                
                if lines.isEmpty {
                    // Empty CSV, write header and first record
                    let header = "project,name,latitude,longitude,altitude,volume"
                    let record = "\(project),\(name),\(latitude),\(longitude),\(altitude),\(volume)"
                    csvContent = header + "\n" + record + "\n"
                    try csvContent.write(to: csvFileURL, atomically: true, encoding: .utf8)
                    print("CSV successfully created: \(csvFileURL.path)")
                    return
                }
                
                if lines[0] != "project,name,latitude,longitude,altitude,volume" {
                    // Header mismatch, overwrite for consistency
                    let header = "project,name,latitude,longitude,altitude,volume"
                    let record = "\(project),\(name),\(latitude),\(longitude),\(altitude),\(volume)"
                    csvContent = header + "\n" + record + "\n"
                    try csvContent.write(to: csvFileURL, atomically: true, encoding: .utf8)
                    print("CSV header updated and record added: \(csvFileURL.path)")
                    return
                }
                
                // Search for existing record
                var recordFound = false
                for i in 1..<lines.count {
                    let line = lines[i]
                    if line.isEmpty { continue }
                    let components = line.components(separatedBy: ",")
                    if components.count >= 2 && components[1] == name {
                        // Record exists, do not overwrite
                        recordFound = true
                        break
                    }
                }
                
                if !recordFound {
                    // Append new record
                    let record = "\(project),\(name),\(latitude),\(longitude),\(altitude),\(volume)"
                    csvContent += record + "\n"
                    try csvContent.write(to: csvFileURL, atomically: true, encoding: .utf8)
                    print("CSV record appended: \(csvFileURL.path)")
                } else {
                    // Record already exists, do not overwrite
                    print("CSV already contains a record for \(name): \(csvFileURL.path)")
                }
            }
            catch {
                print("Failed to process existing CSV: \(error)")
            }
        }
        else {
            // CSV does not exist, create with header and record
            let header = "project,name,latitude,longitude,altitude,volume"
            let record = "\(project),\(name),\(latitude),\(longitude),\(altitude),\(volume)"
            let csvText = header + "\n" + record + "\n"
            do {
                try csvText.write(to: csvFileURL, atomically: true, encoding: .utf8)
                print("CSV successfully created: \(csvFileURL.path)")
            } catch {
                print("Failed to save CSV: \(error)")
            }
        }
    }
    func readCSVCoordinates(fileName: String) -> (latitude: Double, longitude: Double, altitude: Double)? {
        let csvFilePath = self.getDocumentDirectory().appendingPathComponent(fileName).path
        
        // 파일 존재 여부 확인
        guard FileManager.default.fileExists(atPath: csvFilePath) else {
            return nil
        }
        
        do {
            let csvContent = try String(contentsOfFile: csvFilePath, encoding: .utf8)
            let lines = csvContent.components(separatedBy: .newlines)
            
            // 최소 두 줄 (헤더와 데이터)이 있는지 확인
            guard lines.count >= 2 else {
                print("CSV 파일 형식이 올바르지 않습니다.")
                return nil
            }
            
            // 데이터 줄 가져오기
            let dataLine = lines[1]
            let components = dataLine.components(separatedBy: ",")
            
            // Latitude, Longitude, Altitude 순서로 파싱
            if components.count >= 3,
               let latitude = Double(components[2].trimmingCharacters(in: .whitespaces)),
               let longitude = Double(components[3].trimmingCharacters(in: .whitespaces)),
               let altitude = Double(components[4].trimmingCharacters(in: .whitespaces)) {
                return (latitude, longitude, altitude)
            } else {
                print("CSV 데이터 파싱 실패.")
                return nil
            }
        } catch {
            print("CSV 파일 읽기 실패: \(error)")
            return nil
        }
    }
    
    func readCSV(fileName: String, name: String) -> (project: String, longitude: Double, latitude: Double, altitude: Double, volume: Double)? {
        let csvFilePath = self.getDocumentDirectory().appendingPathComponent(fileName).path
        
        // Check if CSV file exists
        guard FileManager.default.fileExists(atPath: csvFilePath) else {
            return nil
        }
        
        do {
            let csvContent = try String(contentsOfFile: csvFilePath, encoding: .utf8)
            let lines = csvContent.components(separatedBy: .newlines)
            
            // Ensure at least header and one data line
            guard lines.count >= 2 else {
                print("CSV file format is invalid.")
                return nil
            }
            
            // Iterate through data lines to find the matching name
            for i in 1..<lines.count {
                let dataLine = lines[i]
                if dataLine.isEmpty { continue }
                let components = dataLine.components(separatedBy: ",")
                
                // project,name,longitude,latitude,altitude,volume
                if components.count >= 6,
                   components[1].trimmingCharacters(in: .whitespaces) == name,
                   let latitude = Double(components[2].trimmingCharacters(in: .whitespaces)),
                   let longitude = Double(components[3].trimmingCharacters(in: .whitespaces)),
                   let altitude = Double(components[4].trimmingCharacters(in: .whitespaces)),
                   let volume = Double(components[5].trimmingCharacters(in: .whitespaces)) {
                    let project = components[0].trimmingCharacters(in: .whitespaces)
                    return (project, longitude, latitude, altitude, volume)
                }
            }
            
            print("No matching record found in CSV for name: \(name)")
            return nil
        } catch {
            print("Failed to read CSV file: \(error)")
            return nil
        }
    }

    func updateVolumeInCSV(fileName: String, name: String, volume: Double) {
        let fileURL = self.getDocumentDirectory().appendingPathComponent(fileName)
        var csvText = ""
        var isUpdated = false
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                var content = try String(contentsOf: fileURL, encoding: .utf8)
                var lines = content.components(separatedBy: .newlines)
                
                // CSV 파일에 헤더가 없다면 헤더 추가
                if lines.isEmpty || lines[0].isEmpty {
                    lines.insert("project,name,longitude,latitude,altitude,volume", at: 0)
                }
                
                for (index, line) in lines.enumerated() {
                    let components = line.components(separatedBy: ",")
                    if components.count >= 6,
                       components[1].trimmingCharacters(in: .whitespacesAndNewlines) == name {
                        // 기존 레코드 업데이트
                        let project = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        let longitude = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
                        let latitude = components[3].trimmingCharacters(in: .whitespacesAndNewlines)
                        let altitude = components[4].trimmingCharacters(in: .whitespacesAndNewlines)
                        lines[index] = "\(project),\(name),\(longitude),\(latitude),\(altitude),\(volume)"
                        isUpdated = true
                        break
                    }
                }
                if !isUpdated {
                    // 새로운 레코드 추가
                    // 기본값으로 longitude, latitude, altitude를 0으로 설정 (필요에 따라 수정)
                    lines.append("Project,\(name),0.0,0.0,0.0,\(volume)")
                }
                csvText = lines.joined(separator: "\n")
            } catch {
                csvText = "project,name,longitude,latitude,altitude,volume\nProject,\(name),0.0,0.0,0.0,\(volume)"
            }
        } else {
            csvText = "project,name,longitude,latitude,altitude,volume\nProject,\(name),0.0,0.0,0.0,\(volume)"
        }
        
        do {
            try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
        }
    }
    
    //MARK: 실데이터 저장
    func saveDatabase(fileName: String) {
        let filePath = self.getDocumentDirectory().appendingPathComponent(fileName).path
        let indicator: UIActivityIndicatorView = UIActivityIndicatorView(style: .large)
        indicator.frame = CGRect(x: 0.0, y: 0.0, width: 60.0, height: 60.0)
        indicator.center = view.center
        view.addSubview(indicator)
        indicator.bringSubviewToFront(view)
        
        indicator.startAnimating()
        
        let previousState = mState;
        updateState(state: .STATE_PROCESSING);
        
        DispatchQueue.background(background: {
            // DB 저장
            self.rtabmap?.save(databasePath: filePath)
            
            if UserDefaults.standard.bool(forKey: "SaveGPS") {
                // 새로운 CSV 파일명 (db파일명 기반)
                let newCSVFileName = (fileName as NSString).deletingPathExtension + ".csv"
                let newCSVFilePath = self.getDocumentDirectory().appendingPathComponent(newCSVFileName)
                
                // 이전 DB 경로가 있고, 그에 해당하는 CSV 파일이 존재하면 rename
                if let oldDBPath = self.openedDatabasePath {
                    let oldCSVFileName = (oldDBPath.lastPathComponent as NSString).deletingPathExtension + ".csv"
                    let oldCSVFilePath = self.getDocumentDirectory().appendingPathComponent(oldCSVFileName)
                    
                    if FileManager.default.fileExists(atPath: oldCSVFilePath.path) {
                        // 기존 CSV가 존재하면 새로운 이름으로 변경
                        do {
                            // 만약 새 CSV 이름과 기존 CSV 이름이 다르다면 rename
                            if oldCSVFilePath.lastPathComponent != newCSVFileName {
                                // 이미 동일한 CSV가 있다면 삭제(덮어쓰기)
                                if FileManager.default.fileExists(atPath: newCSVFilePath.path) {
                                    try FileManager.default.removeItem(at: newCSVFilePath)
                                }
                               // try FileManager.default.moveItem(at: oldCSVFilePath, to: newCSVFilePath)
                            }
                        } catch {
                            print("Failed to rename CSV file: \(error)")
                        }
                    }
                }
                // 새로운 CSV 파일이 없을 경우 현재 위치 기반으로 CSV 생성/추가
                if !FileManager.default.fileExists(atPath: newCSVFilePath.path) {
                    self.saveCSV(fileName: fileName)
                }
            }
            
        }, completion:{
            indicator.stopAnimating()
            indicator.removeFromSuperview()
            
            self.openedDatabasePath = URL(fileURLWithPath: filePath)
            self.infoLabel.text = fileName
            let alert = UIAlertController(title: "Database saved.", message: String(format: "Database \"%@\" successfully saved.", fileName), preferredStyle: .alert)
            let yes = UIAlertAction(title: "OK", style: .default) {
                (UIAlertAction) -> Void in
            }
            alert.addAction(yes)
            self.present(alert, animated: true, completion: nil)
            do {
                let tmpDatabase = self.getDocumentDirectory().appendingPathComponent(self.RTABMAP_TMP_DB)
                try FileManager.default.removeItem(at: tmpDatabase)
            }
            catch {
                print("Could not clear tmp database: \(error)")
            }
            self.updateDatabases()
            self.updateState(state: self.mDataRecording ? .STATE_WELCOME : previousState)
        })
    }

    //MARK: Optimizing Function
    private func export(isOBJ: Bool, meshing: Bool, regenerateCloud: Bool, optimized: Bool, optimizedMaxPolygons: Int, previousState: State)
    {
        let defaults = UserDefaults.standard
        let cloudVoxelSize = defaults.float(forKey: "VoxelSize")
        // Texturesize: Polygonmesh는 0임
        let textureSize = isOBJ ? defaults.integer(forKey: "TextureSize") : 0
        let textureCount = defaults.integer(forKey: "MaximumOutputTextures")
        let normalK = defaults.integer(forKey: "NormalK")
        let maxTextureDistance = defaults.float(forKey: "MaxTextureDistance")
        let minTextureClusterSize = defaults.integer(forKey: "MinTextureClusterSize")
        let optimizedVoxelSize = cloudVoxelSize
        let optimizedDepth = defaults.integer(forKey: "ReconstructionDepth")
        let optimizedColorRadius = defaults.float(forKey: "ColorRadius")
        let optimizedCleanWhitePolygons = defaults.bool(forKey: "CleanMesh")
        let optimizedMinClusterSize = defaults.integer(forKey: "PolygonFiltering")
        let blockRendering = false
        
        var indicator: UIActivityIndicatorView?
        // Optimize 캔슬 화면
        let alertView = UIAlertController(title: "Assembling", message: "Please wait while assembling data...", preferredStyle: .alert)
        alertView.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            self.dismiss(animated: true, completion: {
                self.progressView = nil
                
                indicator = UIActivityIndicatorView(style: .large)
                indicator?.frame = CGRect(x: 0.0, y: 0.0, width: 60.0, height: 60.0)
                indicator?.center = self.view.center
                self.view.addSubview(indicator!)
                indicator?.bringSubviewToFront(self.view)
                
                indicator?.startAnimating()
                
                self.rtabmap!.cancelProcessing()
            })
            
        }))

        updateState(state: .STATE_PROCESSING);
        
        present(alertView, animated: true, completion: {
            //  Add your progressbar after alert is shown (and measured)
            let margin:CGFloat = 8.0
            let rect = CGRect(x: margin, y: 84.0, width: alertView.view.frame.width - margin * 2.0 , height: 2.0)
            self.progressView = UIProgressView(frame: rect)
            self.progressView!.progress = 0
            self.progressView!.tintColor = self.view.tintColor
            alertView.view.addSubview(self.progressView!)
            
            var success : Bool = false
            DispatchQueue.background(background: {
                
                success = self.rtabmap!.exportMesh(
                    cloudVoxelSize: cloudVoxelSize,
                    regenerateCloud: regenerateCloud,
                    meshing: meshing,
                    textureSize: textureSize,
                    textureCount: textureCount,
                    normalK: normalK,
                    optimized: optimized,
                    optimizedVoxelSize: optimizedVoxelSize,
                    optimizedDepth: optimizedDepth,
                    optimizedMaxPolygons: optimizedMaxPolygons,
                    optimizedColorRadius: optimizedColorRadius,
                    optimizedCleanWhitePolygons: optimizedCleanWhitePolygons,
                    optimizedMinClusterSize: optimizedMinClusterSize,
                    optimizedMaxTextureDistance: maxTextureDistance,
                    optimizedMinTextureClusterSize: minTextureClusterSize,
                    blockRendering: blockRendering)
                
            }, completion:{
                if(indicator != nil)
                {
                    indicator!.stopAnimating()
                    indicator!.removeFromSuperview()
                }
                if self.progressView != nil
                {
                    self.dismiss(animated: self.openedDatabasePath == nil, completion: {
                        if(success)
                        {
                            if(!meshing && cloudVoxelSize>0.0)
                            {
                                self.showToast(message: "Cloud assembled and voxelized at \(cloudVoxelSize) m.", seconds: 2)
                            }
                            
                            if(!meshing)
                            {
                                print("!mesh, viewmode: 0")
                                self.setMeshRendering(viewMode: 0)
                            }
                            else if(!isOBJ)
                            {
                                print("!isOBJ, viewmode: 1")
                                self.setMeshRendering(viewMode: 1)
                            }
                            else // isOBJ
                            {
                                print("isOBJ, viewmode: 2")
                                self.setMeshRendering(viewMode: 2)
                            }

                            self.updateState(state: .STATE_VISUALIZING) //Originally STATE_VISUALIZING
                            
                            self.rtabmap!.postExportation(visualize: true)

                            self.setGLCamera(type: 2)
//                            저장할건지 물어봄
                            if self.openedDatabasePath == nil
                            {
                                self.save();
                            }
                        }
                        else
                        {
                            self.updateState(state: previousState);
                            self.showToast(message: "Exporting map failed.", seconds: 4)
                        }
                    })
                }
                else
                {
                    self.showToast(message: "Export canceled", seconds: 2)
                    self.updateState(state: previousState);
                }
            })
        })
    }
    //MARK: OPTIMIZE Function
    private func optimization(withStandardMeshExport: Bool = false, pointcloud: Bool = false, approach: Int)
    {
        if(mState == State.STATE_VISUALIZING)
        {
            closeVisualization()
            rtabmap!.postExportation(visualize: false)
        }
        
        let alertView = UIAlertController(title: "Post-Processing", message: "Please wait while optimizing...", preferredStyle: .alert)
        alertView.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            self.dismiss(animated: true)
            self.progressView = nil
            self.rtabmap!.cancelProcessing()
        }))

        let previousState = mState
        
        updateState(state: .STATE_PROCESSING)
        
        //  Show it to your users
        present(alertView, animated: true, completion: {
            //  Add your progressbar after alert is shown (and measured)
            let margin:CGFloat = 8.0
            let rect = CGRect(x: margin, y: 72.0, width: alertView.view.frame.width - margin * 2.0 , height: 2.0)
            self.progressView = UIProgressView(frame: rect)
            self.progressView!.progress = 0
            self.progressView!.tintColor = self.view.tintColor
            alertView.view.addSubview(self.progressView!)
            
            var loopDetected : Int = -1
            DispatchQueue.background(background: {
                loopDetected = self.rtabmap!.postProcessing(approach: approach);
            }, completion:{
                // main thread
                if self.progressView != nil
                {
                    self.dismiss(animated: self.openedDatabasePath == nil, completion: {
                        self.progressView = nil
                        
                        if(loopDetected >= 0)
                        {
                            if(approach  == -1)
                            {
                                if(withStandardMeshExport)
                                {
                                    //ColoredMesh, TexturedMesh는 isOBJ 차이
                                    self.export(isOBJ: false, meshing: true, regenerateCloud: false, optimized: true, optimizedMaxPolygons: 200000, previousState: previousState);
                                }
                                if(pointcloud)
                                {
                                    self.export(isOBJ: false, meshing: false, regenerateCloud: true, optimized: false, optimizedMaxPolygons: 0, previousState: self.mState)
                                }
                            }
                        }
                        else if(loopDetected < 0)
                        {
                            self.showToast(message: "Optimization failed.", seconds: 4.0)
                        }
                    })
                }
                else
                {
                    self.showToast(message: "Optimization canceled", seconds: 4.0)
                }
                self.updateState(state: .STATE_IDLE);
            })
        })
    }
    
    //MARK: Optimize after Collecting
    func stopMapping(ignoreSaving: Bool) {
        session.pause()
        locationManager?.stopUpdatingLocation()
        rtabmap?.setPausedMapping(paused: true)
        rtabmap?.stopCamera()
        if(mDataRecording) {
            // this will show the trajectory before saving
            self.rtabmap!.setGraphOptimization(enabled: false)
        }
        setGLCamera(type: 2)
        if mState == .STATE_VISUALIZING_CAMERA {
            self.rtabmap?.setLocalizationMode(enabled: false)
        }
        updateState(state: mState == .STATE_VISUALIZING_CAMERA ? .STATE_VISUALIZING : .STATE_IDLE)
        
        //취득 후 Optimzie 및 Assemble
        if !ignoreSaving {
            let depthUsed = self.depthSupported && UserDefaults.standard.bool(forKey: "LidarMode")
            //ColoredMesh Assemble
            self.optimization(withStandardMeshExport: depthUsed, approach: -1)
            
            //포인트클라우드 Max Density Assemble
//            self.optimization(pointcloud: true, approach: -1)
        } else if mMapNodes == 0 {
            updateState(state: .STATE_WELCOME)
            statusLabel.text = ""
        }
    }

    func shareFile(_ fileUrl: URL) {
        let fileURL = NSURL(fileURLWithPath: fileUrl.path)

        // Create the Array which includes the files you want to share
        var filesToShare = [Any]()

        // Add the path of the file to the Array
        filesToShare.append(fileURL)

        // Make the activityViewContoller which shows the share-view
        let activityViewController = UIActivityViewController(activityItems: filesToShare, applicationActivities: nil)
        
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2, width: 0, height: 0)
            popoverController.sourceView = self.view
            popoverController.permittedArrowDirections = UIPopoverArrowDirection(rawValue: 0)
        }

        // Show the share-view
        self.present(activityViewController, animated: true, completion: nil)
    }
    
    // MARK: - File OPEN
    func openDatabase(fileUrl: URL) {
        
        if(mState == .STATE_CAMERA) {
            stopMapping(ignoreSaving: true)
        }
        
        openedDatabasePath = fileUrl
        let fileName: String = self.openedDatabasePath!.lastPathComponent
        infoLabel.text = fileName
        
        let progressDialog = UIAlertController(title: "Loading", message: String(format: "Loading \"%@\". Please wait while point clouds and/or meshes are created...", fileName), preferredStyle: .alert)
        
        // 사용자에게 진행 상황을 표시
        self.present(progressDialog, animated: true)

        updateState(state: .STATE_PROCESSING)
        var status = 0
        DispatchQueue.background(background: {
            self.optimizedGraphShown = true // 데이터베이스를 열 때 항상 true로 초기화
            status = self.rtabmap!.openDatabase(databasePath: self.openedDatabasePath!.path, databaseInMemory: true, optimize: false, clearDatabase: false)
        }, completion:{
            // 메인 스레드
            self.dismiss(animated: true)
            if(status == -1) {
                self.showToast(message: "Failed to optimize the graph, unable to display the map.", seconds: 4)
            }
            else if(status == -2) {
                self.showToast(message: "Not enough memory. Lower the point cloud density in the settings and try again.", seconds: 4)
            }
            else {
                if(status >= 1 && status<=3) {
                    self.updateState(state: .STATE_VISUALIZING)
                    self.resetNoTouchTimer(true)
                }
                else {
                    self.setGLCamera(type: 2)
                    self.updateState(state: .STATE_IDLE)
                    self.showToast(message: "Data has been loaded.", seconds: 2)
                }
                
                // 데이터베이스가 성공적으로 열렸다면 CSV 파일 확인
                if let databasePath = self.openedDatabasePath {
                    let csvFileName = (databasePath.lastPathComponent as NSString).deletingPathExtension + ".csv"
                    let name = (databasePath.lastPathComponent as NSString).deletingPathExtension
                    let csvFileURL = self.getDocumentDirectory().appendingPathComponent(csvFileName)
                    
                    if FileManager.default.fileExists(atPath: csvFileURL.path) {
                        if let csvData = self.readCSV(fileName: csvFileName, name: name) {
                            let volume = csvData.volume
                            DispatchQueue.main.async {
                                self.titleContent.text = "Volume : \(volume) m³"
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.titleContent.text = "Missing Volume"
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.titleContent.text = "Missing Volume"
                        }
                    }
                }
            }
            
        })
    }

    func closeVisualization()
    {
        updateState(state: .STATE_IDLE);
    }
    
    func rename(fileURL: URL)
    {
        //Step : 1
        let alert = UIAlertController(title: "Rename Scan", message: "Database Name (*.db):", preferredStyle: .alert )
        //Step : 2
        let rename = UIAlertAction(title: "Rename", style: .default) { (alertAction) in
            let textField = alert.textFields![0] as UITextField
            if textField.text != "" {
                //Read TextFields text data
                let fileName = textField.text!+".db"
                let filePath = self.getDocumentDirectory().appendingPathComponent(fileName).path
                if FileManager.default.fileExists(atPath: filePath) {
                    let alert = UIAlertController(title: "File Already Exists", message: "Do you want to overwrite the existing file?", preferredStyle: .alert)
                    let yes = UIAlertAction(title: "Yes", style: .default) {
                        (UIAlertAction) -> Void in
                        
                        do {
                            try FileManager.default.moveItem(at: fileURL, to: URL(fileURLWithPath: filePath))
                            print("File \(fileURL) renamed to \(filePath)")
                        }
                        catch {
                            print("Error renaming file \(fileURL) to \(filePath)")
                        }
                        self.openLibrary()
                    }
                    alert.addAction(yes)
                    let no = UIAlertAction(title: "No", style: .cancel) {
                        (UIAlertAction) -> Void in
                    }
                    alert.addAction(no)
                    
                    self.present(alert, animated: true, completion: nil)
                } else {
                    do {
                        try FileManager.default.moveItem(at: fileURL, to: URL(fileURLWithPath: filePath))
                        print("File \(fileURL) renamed to \(filePath)")
                    }
                    catch {
                        print("Error renaming file \(fileURL) to \(filePath)")
                    }
                    self.openLibrary()
                }
            }
        }

        //Step : 3
        alert.addTextField { (textField) in
            var components = fileURL.lastPathComponent.components(separatedBy: ".")
            if components.count > 1 { // If there is a file extension
              components.removeLast()
                textField.text = components.joined(separator: ".")
            } else {
                textField.text = fileURL.lastPathComponent
            }
        }

        //Step : 4
        alert.addAction(rename)
        //Cancel action
        alert.addAction(UIAlertAction(title: "Cancel", style: .default) { (alertAction) in })

        self.present(alert, animated: true) {
            alert.textFields?.first?.selectAll(nil)
        }
    }

//MARK: Export OBJ & PLY
    func exportOBJPLY()
    {
        //Step : 1
        let alert = UIAlertController(title: "Export Scan", message: "Model Name:", preferredStyle: .alert )
        //Step : 2
        let save = UIAlertAction(title: "Ok", style: .default) { (alertAction) in
            let textField = alert.textFields![0] as UITextField
            if textField.text != "" {
                self.dismiss(animated: true)
                //Read TextFields text data
                let fileName = textField.text!+".zip"
                let filePath = self.getDocumentDirectory().appendingPathComponent(fileName).path
                if FileManager.default.fileExists(atPath: filePath) {
                    let alert = UIAlertController(title: "File Already Exists", message: "Do you want to overwrite the existing file?", preferredStyle: .alert)
                    let yes = UIAlertAction(title: "Yes", style: .default) {
                        (UIAlertAction) -> Void in
                        self.writeExportedFiles(fileName: textField.text!);
                    }
                    alert.addAction(yes)
                    let no = UIAlertAction(title: "No", style: .cancel) {
                        (UIAlertAction) -> Void in
                    }
                    alert.addAction(no)
                    
                    self.present(alert, animated: true, completion: nil)
                } else {
                    self.writeExportedFiles(fileName: textField.text!);
                }
            }
        }

        //Step : 3
        alert.addTextField { (textField) in
            if self.openedDatabasePath != nil && !self.openedDatabasePath!.path.isEmpty
            {
                var components = self.openedDatabasePath!.lastPathComponent.components(separatedBy: ".")
                if components.count > 1 { // If there is a file extension
                    components.removeLast()
                    textField.text = components.joined(separator: ".")
                } else {
                    textField.text = self.openedDatabasePath!.lastPathComponent
                }
            }
            else {
                textField.text = Date().getFormattedDate(format: "yyMMdd-HHmmss")
            }
        }

        //Step : 4
        alert.addAction(save)
        //Cancel action
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { (alertAction) in })

        self.present(alert, animated: true) {
            alert.textFields?.first?.selectAll(nil)
        }
    }
    
    func writeExportedFiles(fileName: String) {
        let alertView = UIAlertController(title: "Exporting", message: "Please wait while exporting data to \(fileName)...", preferredStyle: .alert)
        alertView.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            self.dismiss(animated: true)
            self.progressView = nil
            self.rtabmap!.cancelProcessing()
        }))
        
        let previousState = mState

        updateState(state: .STATE_PROCESSING)
        
        present(alertView, animated: true, completion: {
            let margin: CGFloat = 8.0
            let rect = CGRect(x: margin, y: 84.0, width: alertView.view.frame.width - margin * 2.0, height: 2.0)
            self.progressView = UIProgressView(frame: rect)
            self.progressView!.progress = 0
            self.progressView!.tintColor = self.view.tintColor
            alertView.view.addSubview(self.progressView!)
            
            let exportDir = self.getTmpDirectory().appendingPathComponent(self.RTABMAP_EXPORT_DIR)
            
            do {
                try FileManager.default.removeItem(at: exportDir)
            } catch {
                print("Failed to remove existing export directory")
            }
            
            do {
                try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
            } catch {
                print("Failed to create export directory \(exportDir)")
                return
            }
            
            var success: Bool = false
            var exportFileUrl: URL!
            DispatchQueue.background(background: {
                print("Exporting to directory \(exportDir.path) with name \(fileName)")
                
                // 내보내기 처리
                if self.rtabmap!.writeExportedMesh(directory: exportDir.path, name: fileName) {
                    if fileName.hasSuffix(".ply") {
                        print("PLY file exported without compression.")
                        exportFileUrl = exportDir.appendingPathComponent(fileName)
                        success = true
                    } else {
                        do {
                            let fileURLs = try FileManager.default.contentsOfDirectory(at: exportDir, includingPropertiesForKeys: nil)
                            if !fileURLs.isEmpty {
                                do {
                                    exportFileUrl = try Zip.quickZipFiles(fileURLs, fileName: fileName)
                                    print("Zip file \(exportFileUrl.path) created (size=\(exportFileUrl.fileSizeString))")
                                    success = true
                                } catch {
                                    print("Error while zipping files")
                                }
                            }
                        } catch {
                            print("No files exported to \(exportDir)")
                            return
                        }
                    }
                }
                
            }, completion: {
                if self.progressView != nil {
                    self.dismiss(animated: true)
                }
                if success {
                    let alertSaved = UIAlertController(
                        title: "Export Complete",
                        message: "\(fileName) successfully exported.",
                        preferredStyle: .alert
                    )
                    let alertActionOk = UIAlertAction(title: "OK", style: .cancel, handler: nil)
                    alertSaved.addAction(alertActionOk)
                    self.present(alertSaved, animated: true, completion: nil)
                } else {
                    self.showToast(message: "Exporting canceled.", seconds: 2)
                }
                self.updateState(state: previousState)
            })
        })
    }

    func updateDatabases()
    {
        databases.removeAll()
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: getDocumentDirectory(), includingPropertiesForKeys: nil)

            let data = fileURLs.map { url in
                        (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast)
                    }
                    .sorted(by: { $0.1 > $1.1 }) // sort descending modification dates
                    .map { $0.0 } // extract file names
            databases = data.filter{ $0.pathExtension == "db" && $0.lastPathComponent != RTABMAP_TMP_DB && $0.lastPathComponent != RTABMAP_RECOVERY_DB }
            
        } catch {
            print("Error while enumerating files : \(error.localizedDescription)")
            return
        }

    }
    
    func openLibrary()
    {
        updateDatabases();
        
        if databases.isEmpty {
            return
        }
        let alertController = UIAlertController(title: "Library", message: nil, preferredStyle: .alert)
        let customView = VerticalScrollerView()
        customView.dataSource = self
        customView.delegate = self
        customView.reload()
        alertController.view.addSubview(customView)
        customView.translatesAutoresizingMaskIntoConstraints = false
        customView.topAnchor.constraint(equalTo: alertController.view.topAnchor, constant: 60).isActive = true
        customView.rightAnchor.constraint(equalTo: alertController.view.rightAnchor, constant: -10).isActive = true
        customView.leftAnchor.constraint(equalTo: alertController.view.leftAnchor, constant: 10).isActive = true
        customView.bottomAnchor.constraint(equalTo: alertController.view.bottomAnchor, constant: -45).isActive = true
        
        alertController.view.translatesAutoresizingMaskIntoConstraints = false
        alertController.view.heightAnchor.constraint(equalToConstant: 600).isActive = true
        alertController.view.widthAnchor.constraint(equalToConstant: 400).isActive = true

        customView.backgroundColor = .darkGray

        let selectAction = UIAlertAction(title: "Select", style: .default) { [weak self] (action) in
            guard let self = self else { return }
            
            // 인덱스 유효성 검사
            if self.currentDatabaseIndex >= 0 && self.currentDatabaseIndex < self.databases.count {
                let fileUrl = self.databases[self.currentDatabaseIndex]
                self.openDatabase(fileUrl: fileUrl)
            } else {
                // 오류 팝업 메시지 생성
                let errorAlert = UIAlertController(title: "Index Error", message: "Try Again.", preferredStyle: .alert)
                
                // 현재 뷰 컨트롤러에서 오류 팝업 표시
                self.present(errorAlert, animated: true, completion: nil)
            }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(selectAction)
        alertController.addAction(cancelAction)
        self.present(alertController, animated: true, completion: nil)
    }

    //MARK: Actions
    @objc func backButtonTapped() {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func stopAction(_ sender: UIButton) {
        stopMapping(ignoreSaving: false)
    }
    
    @IBAction func newScanAction(_ sender: UIButton) {
        newScan()
    }
    
    @IBAction func recordAction(_ sender: UIButton) {
        rtabmap?.setPausedMapping(paused: false);
        updateState(state: .STATE_MAPPING)
    }

    @IBAction func switchAction(_ sender: UIButton) {
        if(viewMode == 0){
            self.setMeshRendering(viewMode: 2)
//            infoLabel.text = "Mesh View"
        }
//        else if(viewMode == 1){
//            self.setMeshRendering(viewMode: 2)
//            print("viewmode 2")
//            infoLabel.text = "Mesh View"
//        }
        else {
            self.setMeshRendering(viewMode: 0)
//            infoLabel.text = "Point Cloud View"
        }
    }
    
    @IBAction func closeVisualizationAction(_ sender: UIButton) {
        closeVisualization()
        rtabmap!.postExportation(visualize: false)
    }
    
    @IBAction func stopCameraAction(_ sender: UIButton) {
        appMovedToBackground();
    }
    
//    @IBAction func exportOBJPLYAction(_ sender: UIButton) {
//        exportOBJPLY()
//    }
    
    @IBAction func libraryAction(_ sender: UIButton) {
        openLibrary();
    }
    
    @IBAction func projectAction(_ sender: UIButton) {
        showProjectSelectionPopup(cancel: true);
    }
    
    @IBAction func rotateGridAction(_ sender: UISlider) {
//        rtabmap!.setGridRotation((Float(sender.value)-90.0)/2.0)
        if(viewMode == 0){
            // raw : 0 ~ 180
            let point_size = (round(Float(sender.value) / 9))
            rtabmap!.setPointSize(value: point_size)
            self.view.setNeedsDisplay()
        }
    }
    @IBAction func clipDistanceAction(_ sender: UISlider) {
        rtabmap!.setOrthoCropFactor(Float(120-sender.value)/20.0 - 3.0)
        self.view.setNeedsDisplay()
    }
    
    @IBAction func saveButtonTapped(_ sender: UIButton) {
        exportOBJPLY()
    }
    
    @IBAction func editButtonTapped(_ sender: UIButton) {
        if(mState == State.STATE_EDIT){
            self.showToast(message: "Measurement Mode OFF", seconds: 3)
            editButton.tintColor = .systemYellow
            self.updateState(state: .STATE_VISUALIZING)
            self.rtabmap!.setWireframe(enabled: false)
            self.closeVisualization()
            rtabmap?.removePoint();
            if self.isPaused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.view.setNeedsDisplay()
                }
            }
            if let databasePath = self.openedDatabasePath {
                let csvFileName = (databasePath.lastPathComponent as NSString).deletingPathExtension + ".csv"
                let name = (databasePath.lastPathComponent as NSString).deletingPathExtension
                let csvFileURL = self.getDocumentDirectory().appendingPathComponent(csvFileName)
                if FileManager.default.fileExists(atPath: csvFileURL.path) {
                    if let csvData = self.readCSV(fileName: csvFileName, name: name) {
                        let volume = csvData.volume
                        self.titleContent.text = "Volume : \(volume) m³"
                    }
                } else {
                    DispatchQueue.main.async {
                        self.titleContent.text = "Missing Volume"
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.titleContent.text = "Missing Volume"
                }
            }
        }
        else{
            self.showToast(message: "Measurement Mode ON", seconds: 3)
            editButton.tintColor = .systemRed
            self.updateState(state: .STATE_EDIT)
            self.rtabmap!.setWireframe(enabled: true)
            self.titleContent.text = "Volume : 0 m³"
        }
    }

    @IBAction func mapButtonTapped(_ sender: UIButton) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        
        if let scanSceneVC = storyboard.instantiateViewController(withIdentifier: "mapScene") as? MapViewController {
            // 네비게이션 컨트롤러가 없을 경우 모달 방식으로 표시
            scanSceneVC.modalPresentationStyle = .fullScreen // 필요에 따라 스타일 조정
            scanSceneVC.modalTransitionStyle = .coverVertical
            self.present(scanSceneVC, animated: true, completion: nil)
        } else {
            print("Error: 'mapScene' 뷰 컨트롤러를 'ViewController' 클래스로 캐스팅할 수 없습니다.")
        }
    }
    
    @IBAction func cropButtonTapped(_ sender: UIButton) {
        isCropping.toggle()
        editsaveButton.isEnabled = !isCropping
        editButton.isHidden = isCropping
        
        if isCropping {
            self.showToast(message: "Cropping ON", seconds: 4)
            cropButton.tintColor = .systemRed
        } else {
            self.showToast(message: "Cropping OFF", seconds: 4)
            cropButton.tintColor = .white
        }
    }
    
    @IBAction func cancelButtonTapped(_ sender: UIButton) {
        rtabmap?.removePoint();
        if self.isPaused {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                self.view.setNeedsDisplay()
            }
        }
    }
    
    @IBAction func editsaveButtonTapped(_ sender: UIButton) {
        //Volume Calculation
        self.showToast(message: "The volume has been calculated.", seconds: 4)
        let showvolume = round(1000 * rtabmap!.calculateMeshVolume()) / 1000
        self.titleContent.text = "Volume : \(showvolume) m³"
        
        // Update the CSV with the new volume
        if let databasePath = self.openedDatabasePath {
            let csvFileName = (databasePath.lastPathComponent as NSString).deletingPathExtension + ".csv"
            let name = (databasePath.lastPathComponent as NSString).deletingPathExtension
            self.updateVolumeInCSV(fileName: csvFileName, name: name, volume: showvolume)
        }
    }
}

func clearBackgroundColor(of view: UIView) {
    if let effectsView = view as? UIVisualEffectView {
        effectsView.removeFromSuperview()
        return
    }

    view.backgroundColor = .clear
    view.subviews.forEach { (subview) in
        clearBackgroundColor(of: subview)
    }
}

extension ViewController: GLKViewControllerDelegate {
    
    // OPENGL UPDATE
    func glkViewControllerUpdate(_ controller: GLKViewController) {
        
    }
    
    // OPENGL DRAW
    override func glkView(_ view: GLKView, drawIn rect: CGRect) {
        if let rotation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation
        {
            let viewportSize = CGSize(width: rect.size.width * view.contentScaleFactor, height: rect.size.height * view.contentScaleFactor)
            rtabmap?.setupGraphic(size: viewportSize, orientation: rotation)
        }
        
        let value = rtabmap?.render()
        
        DispatchQueue.main.async {
            if(value != 0 && self.progressView != nil)
            {
                print("Render dismissing")
                self.dismiss(animated: true)
                self.progressView = nil
                
            }
            if(value == -1)
            {
                self.showToast(message: "Out of Memory.", seconds: 2)
            }
            else if(value == -2)
            {
                self.showToast(message: "Rendering Error.", seconds: 2)
            }
        }
    }
}

extension Date {
   func getFormattedDate(format: String) -> String {
        let dateformat = DateFormatter()
        dateformat.dateFormat = format
        return dateformat.string(from: self)
    }
    
    var millisecondsSince1970:Int64 {
        Int64((self.timeIntervalSince1970 * 1000.0).rounded())
    }
    
    init(milliseconds:Int64) {
        self = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }
}

extension DispatchQueue {

    static func background(delay: Double = 0.0, background: (()->Void)? = nil, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            background?()
            if let completion = completion {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: {
                    completion()
                })
            }
        }
    }
}

extension ViewController: VerticalScrollerViewDelegate {
    func verticalScrollerView(_ horizontalScrollerView: VerticalScrollerView, didSelectViewAt index: Int) {
    //1
    let previousDatabaseView = horizontalScrollerView.view(at: currentDatabaseIndex) as! DatabaseView
    previousDatabaseView.highlightDatabase(false)
    //2
    currentDatabaseIndex = index
    //3
    let databaseView = horizontalScrollerView.view(at: currentDatabaseIndex) as! DatabaseView
    databaseView.highlightDatabase(true)
    //4
  }
}

extension ViewController: VerticalViewDataSource {
  func numberOfViews(in horizontalScrollerView: VerticalScrollerView) -> Int {
    return databases.count
  }
  
  func getScrollerViewItem(_ horizontalScrollerView: VerticalScrollerView, viewAt index: Int) -> UIView {
    print(databases[index].path)
    let databaseView = DatabaseView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), databaseURL: databases[index])

    databaseView.delegate = self
    
    if currentDatabaseIndex == index {
        databaseView.highlightDatabase(true)
    } else {
        databaseView.highlightDatabase(false)
    }

    return databaseView
  }
}

extension ViewController: DatabaseViewDelegate {
    func databaseShared(databaseURL: URL) {
//        self.dismiss(animated: true)
//        self.shareFile(databaseURL)
    }
    
    func databaseRenamed(databaseURL: URL) {
        self.dismiss(animated: true)
        
        if(openedDatabasePath?.lastPathComponent == databaseURL.lastPathComponent)
        {
            let alertController = UIAlertController(title: "Rename Database", message: "Database \(databaseURL.lastPathComponent) is already opened, cannot rename it.", preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .default) { (action) in
            }
            alertController.addAction(okAction)
            present(alertController, animated: true)
            return
        }
        
        self.rename(fileURL: databaseURL)
    }
    
    func databaseDeleted(databaseURL: URL) {
        self.dismiss(animated: true)
        
        if(openedDatabasePath?.lastPathComponent == databaseURL.lastPathComponent)
        {
            let alertController = UIAlertController(title: "Delete Database", message: "Database \(databaseURL.lastPathComponent) is already opened, cannot delete it.", preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .default) { (action) in
            }
            alertController.addAction(okAction)
            present(alertController, animated: true)
            return
        }
        
        do {
            try FileManager.default.removeItem(at: databaseURL)
            print("File \(databaseURL) deleted")
            
            // CSV 파일 경로 생성
            let csvFileName = (databaseURL.lastPathComponent as NSString).deletingPathExtension + ".csv"
            let csvFilePath = self.getDocumentDirectory().appendingPathComponent(csvFileName)
            
            // CSV 파일이 존재하면 삭제
            if FileManager.default.fileExists(atPath: csvFilePath.path) {
                do {
                    try FileManager.default.removeItem(at: csvFilePath)
                    print("CSV \(csvFilePath) deleted")
                } catch {
                    print("Error deleting CSV file \(csvFilePath): \(error)")
                }
            }
        }
        catch {
            print("Error deleting file \(databaseURL): \(error)")
        }
        
        self.updateDatabases()
        if(!databases.isEmpty)
        {
            self.openLibrary()
        }
        else {
            self.updateState(state: self.mState)
        }
    }

  }

extension UserDefaults {
    func reset() {
        let defaults = UserDefaults.standard
        defaults.dictionaryRepresentation().keys.forEach(defaults.removeObject(forKey:))
        
        setDefaultsFromSettingsBundle()
    }
}

class PolygonOverlayView: UIView {
    var polygonPoints: [CGPoint] = []
    var isClosed: Bool = false
    
    func addPolygon(points: [CGPoint]) {
        self.polygonPoints = points
        self.isClosed = true
        setNeedsDisplay()
    }
    
    func clear() {
        self.polygonPoints.removeAll()
        self.isClosed = false
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        guard polygonPoints.count > 1 else { return }
        
        let path = UIBezierPath()
        path.move(to: polygonPoints[0])
        for point in polygonPoints.dropFirst() {
            path.addLine(to: point)
        }
        if isClosed {
            path.close()
            UIColor.systemPink.setFill()
            path.fill()
        }
        
        UIColor.systemPink.setStroke()
        path.lineWidth = 2.0
        path.stroke()
    }
}
