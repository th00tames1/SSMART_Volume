//
//  Main.swift
//  SlashScan
//
//  Created by HC on 9/18/24.
//

import UIKit
import MapKit
import CoreLocation

// MARK: - CustomAnnotation Class
class CustomAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    var isCSV: Bool
    var csvFileName: String?
    var altitude: Double?
    var project: String?
    var name: String?
    var volume: Double?

    init(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?, isCSV: Bool, csvFileName: String?, altitude: Double?, project: String?, name: String?, volume: Double?) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.isCSV = isCSV
        self.csvFileName = csvFileName
        self.altitude = altitude
        self.project = project
        self.name = name
        self.volume = volume
    }
}

// MARK: - FileInfo
struct FileInfo {
    var fileName: String
    var hasCoordinates: Bool
    var latitude: Double?
    var longitude: Double?
    var project: String?
    var name: String?
    var altitude: Double?
    var volume: Double?
}

// MARK: - MapViewController
class MapViewController: UIViewController, CLLocationManagerDelegate, UIGestureRecognizerDelegate {

    var mapView: MKMapView!
    let locationManager = CLLocationManager()
    var compassButton: MKCompassButton!
    var scaleView: MKScaleView!

    var locateButton: UIButton!
    var mapTypeButton: UIButton!
    var addButton: UIButton!
    var editcoordsButton: UIButton!
    var searchBar: UISearchBar!

    var tableView: UITableView!
    var searchCompleter: MKLocalSearchCompleter!
    var searchResults = [MKLocalSearchCompletion]()

    var scannedFiles: [FileInfo] = []
    let geocoder = CLGeocoder()

    var longPressGesture: UILongPressGestureRecognizer!
    var doubleTapGesture: UITapGestureRecognizer!
    var pinCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        mapView = MKMapView(frame: view.frame)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        mapView.mapType = .hybrid
        view.addSubview(mapView)

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()

        if CLLocationManager.locationServicesEnabled() {
            locationManager.startUpdatingLocation()
            mapView.showsUserLocation = true
        }

        setupCompassButton()
        setupScaleView()
        setupLocateButton()
        setupMapTypeButton()
        setupAddButton()
        setupeditcoordsButton()
        setupSearchBar()
        setupSearchCompleter()
        setupTableView()
        setupDoubleTapGestureRecognizer()
        setupLongPressGestureRecognizer()

        loadAnnotationsFromCSV()
        loadPinpointsFromCSV()

        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
    }

    func getDocumentDirectory() -> URL {
        if let projectPath = UserDefaults.standard.string(forKey: "SelectedProjectFolder"),
           !projectPath.isEmpty {
            let projectURL = URL(fileURLWithPath: projectPath)
            if FileManager.default.fileExists(atPath: projectURL.path) {
                return projectURL
            }
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            let center = CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            let region = MKCoordinateRegion(center: center, latitudinalMeters: 2000, longitudinalMeters: 2000)
            mapView.setRegion(region, animated: true)
            locationManager.stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to get location: \(error.localizedDescription)")
        showAlert(title: "Location Error", message: error.localizedDescription)
    }

    func setupCompassButton() {
        compassButton = MKCompassButton(mapView: mapView)
        compassButton.compassVisibility = .visible
        compassButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(compassButton)

        NSLayoutConstraint.activate([
            compassButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            compassButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10)
        ])
    }

    func setupScaleView() {
        scaleView = MKScaleView(mapView: mapView)
        scaleView.legendAlignment = .trailing
        scaleView.scaleVisibility = .visible
        scaleView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scaleView)

        NSLayoutConstraint.activate([
            scaleView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            scaleView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10)
        ])
    }

    func setupMapTypeButton() {
        mapTypeButton = UIButton(type: .system)
        mapTypeButton.translatesAutoresizingMaskIntoConstraints = false
        mapTypeButton.backgroundColor = .systemGray
        mapTypeButton.setImage(UIImage(systemName: "map"), for: .normal)
        mapTypeButton.tintColor = .white
        mapTypeButton.layer.cornerRadius = 30
        mapTypeButton.clipsToBounds = true
        mapTypeButton.layer.shadowColor = UIColor.black.cgColor
        mapTypeButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        mapTypeButton.layer.shadowOpacity = 0.3
        mapTypeButton.layer.shadowRadius = 2
        mapTypeButton.addTarget(self, action: #selector(mapTypeButtonTapped), for: .touchUpInside)
        view.addSubview(mapTypeButton)

        NSLayoutConstraint.activate([
            mapTypeButton.widthAnchor.constraint(equalToConstant: 60),
            mapTypeButton.heightAnchor.constraint(equalToConstant: 60),
            mapTypeButton.bottomAnchor.constraint(equalTo: scaleView.topAnchor, constant: -10),
            mapTypeButton.trailingAnchor.constraint(equalTo: locateButton.leadingAnchor, constant: -10)
        ])
    }

    func setupLocateButton() {
        locateButton = UIButton(type: .system)
        locateButton.translatesAutoresizingMaskIntoConstraints = false
        locateButton.backgroundColor = .systemBlue
        locateButton.setImage(UIImage(systemName: "location.fill"), for: .normal)
        locateButton.tintColor = .white
        locateButton.layer.cornerRadius = 30
        locateButton.clipsToBounds = true
        locateButton.layer.shadowColor = UIColor.black.cgColor
        locateButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        locateButton.layer.shadowOpacity = 0.3
        locateButton.layer.shadowRadius = 2
        locateButton.addTarget(self, action: #selector(locateButtonTapped), for: .touchUpInside)
        view.addSubview(locateButton)

        NSLayoutConstraint.activate([
            locateButton.widthAnchor.constraint(equalToConstant: 60),
            locateButton.heightAnchor.constraint(equalToConstant: 60),
            locateButton.bottomAnchor.constraint(equalTo: scaleView.topAnchor, constant: -10),
            locateButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10)
        ])
    }
    
    func setupAddButton() {
        // 흰색 원을 위한 UIView 생성
        let circleView = UIView()
        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.backgroundColor = .white
        circleView.layer.cornerRadius = 20 // 반지름 20
        circleView.layer.masksToBounds = true
        view.addSubview(circleView)
        
        // 버튼 생성
        addButton = UIButton(type: .system)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.setBackgroundImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        addButton.tintColor = .systemBlue
        addButton.clipsToBounds = true
        addButton.addTarget(self, action: #selector(addButtonTapped), for: .touchUpInside)
        view.addSubview(addButton)
        
        // 오토레이아웃 제약조건 설정
        NSLayoutConstraint.activate([
            // 흰색 원의 크기 및 위치 설정
            circleView.widthAnchor.constraint(equalToConstant: 40),
            circleView.heightAnchor.constraint(equalToConstant: 40),
            circleView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            circleView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -25),
            addButton.widthAnchor.constraint(equalToConstant: 70),
            addButton.heightAnchor.constraint(equalToConstant: 70),
            addButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10)
        ])
    }

    
    func setupeditcoordsButton() {
        editcoordsButton = UIButton(type: .system)
        editcoordsButton.translatesAutoresizingMaskIntoConstraints = false
        editcoordsButton.backgroundColor = .systemGreen
        editcoordsButton.setImage(UIImage(systemName: "globe"), for: .normal)
        editcoordsButton.tintColor = .white
        editcoordsButton.layer.cornerRadius = 30
        editcoordsButton.clipsToBounds = true
        editcoordsButton.layer.shadowColor = UIColor.black.cgColor
        editcoordsButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        editcoordsButton.layer.shadowOpacity = 0.3
        editcoordsButton.layer.shadowRadius = 2
        editcoordsButton.addTarget(self, action: #selector(editcoordsButtonTapped), for: .touchUpInside)
        view.addSubview(editcoordsButton)

        NSLayoutConstraint.activate([
            editcoordsButton.widthAnchor.constraint(equalToConstant: 60),
            editcoordsButton.heightAnchor.constraint(equalToConstant: 60),
            editcoordsButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            editcoordsButton.bottomAnchor.constraint(equalTo: scaleView.topAnchor, constant: -10)
        ])
    }

    func setupSearchBar() {
        searchBar = UISearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = "Search..."
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundImage = UIImage()
        searchBar.backgroundColor = .clear

        if let textField = searchBar.value(forKey: "searchField") as? UITextField {
            textField.backgroundColor = .white
//            textField.layer.cornerRadius = 25
            textField.layer.masksToBounds = true
            textField.layer.borderWidth = 0
            textField.textColor = .black
        }

        view.addSubview(searchBar)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60),
            searchBar.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    func setupSearchCompleter() {
        searchCompleter = MKLocalSearchCompleter()
        searchCompleter.delegate = self
        searchCompleter.resultTypes = .address
    }

    func setupTableView() {
        tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.isHidden = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SearchResultCell")
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            tableView.heightAnchor.constraint(equalToConstant: 200)
        ])
    }

    // fileListTableView 제거

    func setupDoubleTapGestureRecognizer() {
        doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.delegate = self
        mapView.addGestureRecognizer(doubleTapGesture)
    }

    func setupLongPressGestureRecognizer() {
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.delegate = self
        mapView.addGestureRecognizer(longPressGesture)
    }

    @objc func locateButtonTapped() {
        if let userLocation = mapView.userLocation.location {
            let center = CLLocationCoordinate2D(latitude: userLocation.coordinate.latitude, longitude: userLocation.coordinate.longitude)
            let region = MKCoordinateRegion(center: center, latitudinalMeters: 2000, longitudinalMeters: 2000)
            mapView.setRegion(region, animated: true)
        }
    }

    @objc func mapTypeButtonTapped() {
        switch mapView.mapType {
        case .hybrid:
            mapView.mapType = .standard
            mapTypeButton.setImage(UIImage(systemName: "map"), for: .normal)
        default:
            mapView.mapType = .hybrid
            mapTypeButton.setImage(UIImage(systemName: "map.fill"), for: .normal)
        }
    }

    @objc func addButtonTapped() {
        dismiss(animated: true)
    }

    // MARK: - 팝업 버튼 동작
    @objc func editcoordsButtonTapped() {
        // CSV 파일 스캔
        scannedFiles = scanCSVFiles()

        // UIAlertController 생성
        let alertController = UIAlertController(title: "Edit Longitude/Latitude", message: nil, preferredStyle: .actionSheet)

        // 각 CSV 파일을 UIAlertAction으로 추가
        for file in scannedFiles {
            let title = file.hasCoordinates ? file.fileName : "\(file.fileName) (No Coordinates)"
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.presentCoordinateEditAlert(for: file)
            }
            alertController.addAction(action)
        }

        // 취소 버튼 추가
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(cancelAction)

        // iPad 대응 (PopoverPresentationController 설정)
        if let popoverController = alertController.popoverPresentationController {
            popoverController.sourceView = editcoordsButton
            popoverController.sourceRect = editcoordsButton.bounds
        }

        // UIAlertController 표시
        present(alertController, animated: true, completion: nil)
    }

    func scanCSVFiles() -> [FileInfo] {
        var results: [FileInfo] = []
        let documentsURL = getDocumentDirectory()
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            let csvFiles = fileURLs.filter { $0.pathExtension.lowercased() == "csv" }

            var noCoords: [FileInfo] = []
            var withCoords: [FileInfo] = []

            for fileURL in csvFiles {
                let baseFilename = fileURL.deletingPathExtension().lastPathComponent
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                
                // pinpoints.csv 제외
                if baseFilename.lowercased() == "pinpoints" {
                    continue
                }

                guard lines.count > 1 else {
                    noCoords.append(FileInfo(fileName: baseFilename, hasCoordinates: false, latitude: nil, longitude: nil, project: nil, name: nil, altitude: nil, volume: nil))
                    continue
                }

                let headerLine = lines[0]
                let headers = headerLine.components(separatedBy: ",").map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

                let latitudeIndex = headers.firstIndex(of: "latitude")
                let longitudeIndex = headers.firstIndex(of: "longitude")
                let projectIndex = headers.firstIndex(of: "project")
                let nameIndex = headers.firstIndex(of: "name")
                let altitudeIndex = headers.firstIndex(of: "altitude")
                let volumeIndex = headers.firstIndex(of: "volume")

                let firstDataLine = lines[1]
                let fields = firstDataLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

                var lat: Double? = nil
                var lon: Double? = nil
                var proj: String? = nil
                var fname: String? = nil
                var alt: Double? = nil
                var vol: Double? = nil

                if let laIdx = latitudeIndex, laIdx < fields.count, let latVal = Double(fields[laIdx]) {
                    lat = latVal
                }
                if let loIdx = longitudeIndex, loIdx < fields.count, let lonVal = Double(fields[loIdx]) {
                    lon = lonVal
                }
                if let pIdx = projectIndex, pIdx < fields.count {
                    proj = fields[pIdx]
                }
                if let nIdx = nameIndex, nIdx < fields.count {
                    fname = fields[nIdx]
                }
                if let aIdx = altitudeIndex, aIdx < fields.count, let aVal = Double(fields[aIdx]) {
                    alt = aVal
                }
                if let vIdx = volumeIndex, vIdx < fields.count, let vVal = Double(fields[vIdx]) {
                    vol = vVal
                }

                if lat == nil || lon == nil {
                    noCoords.append(FileInfo(fileName: baseFilename, hasCoordinates: false, latitude: nil, longitude: nil, project: proj, name: fname, altitude: alt, volume: vol))
                } else {
                    withCoords.append(FileInfo(fileName: baseFilename, hasCoordinates: true, latitude: lat, longitude: lon, project: proj, name: fname, altitude: alt, volume: vol))
                }
            }

            results = noCoords + withCoords
            return results

        } catch {
            print("Error scanning CSV files: \(error)")
            showAlert(title: "Scan Error", message: "Failed to scan CSV files: \(error.localizedDescription)")
            return []
        }
    }

    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        // 임시용
    }

    //길게 눌러 핀포인트 생성
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            let touchPoint = gesture.location(in: mapView)
            let coordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
            createPinpoint(at: coordinate)
        }
    }
    
    // 핀포인트 생성 실제 함수
    func createPinpoint(at coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        pinCount += 1
        let pinTitle = "Pin \(pinCount)"

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }

            if let error = error {
                print("Reverse geocoding failed: \(error.localizedDescription)")
                self.showAlert(title: "Failed to get address", message: error.localizedDescription)
                return
            }

            var addressString = ""
            if let placemark = placemarks?.first {
                if let name = placemark.name { addressString += name }
                if let thoroughfare = placemark.thoroughfare { addressString += " \(thoroughfare)" }
                if let locality = placemark.locality { addressString += " \(locality)" }
                if let administrativeArea = placemark.administrativeArea { addressString += "  \(administrativeArea)" }
                if let country = placemark.country { addressString += " \(country)" }
            }

            let message = [
                "Address: \(addressString)",
                String(format: "Latitude: %.6f", coordinate.latitude),
                String(format: "Longitude: %.6f", coordinate.longitude)
            ].joined(separator: "\n")

            let annotation = CustomAnnotation(
                coordinate: coordinate,
                title: pinTitle,
                subtitle: message,
                isCSV: false,
                csvFileName: nil,
                altitude: nil,
                project: nil,
                name: pinTitle,
                volume: nil
            )
            self.mapView.addAnnotation(annotation)
            self.savePinpointsToCSV()
        }
    }

    func updateCSVFile(fileInfo: FileInfo, newLat: Double, newLon: Double) {
        let docURL = getDocumentDirectory().appendingPathComponent(fileInfo.fileName + ".csv")
        guard FileManager.default.fileExists(atPath: docURL.path) else {
            showAlert(title: "Error", message: "Cannot find the file.")
            return
        }
        if fileInfo.fileName.lowercased() == "pinpoints" {
            return
        }

        do {
            let content = try String(contentsOf: docURL, encoding: .utf8)
            var lines = content.components(separatedBy: .newlines)
            guard lines.count > 1 else { return }

            let headerLine = lines[0]
            let headers = headerLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

            guard let latIndex = headers.firstIndex(where: { $0.lowercased() == "latitude" }),
                  let lonIndex = headers.firstIndex(where: { $0.lowercased() == "longitude" }) else {
                showAlert(title: "Error", message: "Data does not contain latitude or longitude columns.")
                return
            }

            var dataLine = lines[1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if latIndex < dataLine.count && lonIndex < dataLine.count {
                dataLine[latIndex] = "\(newLat)"
                dataLine[lonIndex] = "\(newLon)"
                lines[1] = dataLine.joined(separator: ",")
            }

            let newContent = lines.joined(separator: "\n")
            try newContent.write(to: docURL, atomically: true, encoding: .utf8)
            showAlert(title: "Save Complete", message: "Coordinates have been updated.")

        } catch {
            showAlert(title: "Error", message: "Failed to update the file: \(error.localizedDescription)")
        }
    }

    func presentCoordinateEditAlert(for fileInfo: FileInfo) {
        let alert = UIAlertController(title: "Edit Coordinates for '\(fileInfo.fileName)'", message: "Please enter new latitude, longitude and altitude.", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Latitude"
            if let lat = fileInfo.latitude {
                textField.text = "\(lat)"
            }
            textField.keyboardType = .decimalPad
        }
        alert.addTextField { textField in
            textField.placeholder = "Longitude"
            if let lon = fileInfo.longitude {
                textField.text = "\(lon)"
            }
            textField.keyboardType = .decimalPad
        }
        alert.addTextField { textField in
            textField.placeholder = "Altitude"
            if let lon = fileInfo.altitude {
                textField.text = "\(lon)"
            }
            textField.keyboardType = .decimalPad
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
            guard let latText = alert.textFields?[0].text, let latVal = Double(latText),
                  let lonText = alert.textFields?[1].text, let lonVal = Double(lonText) else {
                self.showAlert(title: "Error", message: "Please enter valid numbers.")
                return
            }
            self.updateCSVFile(fileInfo: fileInfo, newLat: latVal, newLon: lonVal)
        }))
        present(alert, animated: true)
    }

    func pinpointsCSVURL() -> URL {
        return getDocumentDirectory().appendingPathComponent("pinpoints.csv")
    }

    func loadPinpointsFromCSV() {
        let fileURL = pinpointsCSVURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            guard lines.count > 1 else { return }

            let header = lines[0].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let nameIndex = header.firstIndex(of: "name"),
                  let latIndex = header.firstIndex(of: "latitude"),
                  let lonIndex = header.firstIndex(of: "longitude"),
                  let addressIndex = header.firstIndex(of: "address") else {
                return
            }

            for line in lines.dropFirst() {
                let fields = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if fields.count < header.count { continue }

                let name = fields[nameIndex]
                guard let latitude = Double(fields[latIndex]),
                      let longitude = Double(fields[lonIndex]) else { continue }
                let address = fields[addressIndex]

                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                let annotation = CustomAnnotation(
                    coordinate: coordinate,
                    title: name,
                    subtitle: "Address: \(address)\nLatitude: \(latitude)\nLongitude: \(longitude)",
                    isCSV: false,
                    csvFileName: nil,
                    altitude: nil,
                    project: nil,
                    name: name,
                    volume: nil
                )
                mapView.addAnnotation(annotation)
            }

        } catch {
            print("Failed to load pinpoints.csv: \(error.localizedDescription)")
            showAlert(title: "Load Error", message: "Failed to load pinpoints: \(error.localizedDescription)")
        }
    }

    func savePinpointsToCSV() {
        let userPinpoints = mapView.annotations.compactMap { $0 as? CustomAnnotation }.filter { !$0.isCSV }

        var csvString = "name,latitude,longitude,address\n"
        for pinpoint in userPinpoints {
            let lat = pinpoint.coordinate.latitude
            let lon = pinpoint.coordinate.longitude
            var address = ""
            if let subtitle = pinpoint.subtitle {
                let lines = subtitle.components(separatedBy: "\n")
                if let addrLine = lines.first(where: { $0.starts(with: "Address: ") }) {
                    address = String(addrLine.dropFirst("Address: ".count))
                }
            }
            let safeName = (pinpoint.title?.contains(",") == true) ? "\"\(pinpoint.title ?? "")\"" : (pinpoint.title ?? "")
            let safeAddress = address.contains(",") ? "\"\(address)\"" : address
            csvString += "\(safeName),\(lat),\(lon),\(safeAddress)\n"
        }

        let fileURL = pinpointsCSVURL()
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            print("pinpoints.csv saved successfully.")
        } catch {
            print("Failed to save pinpoints.csv: \(error.localizedDescription)")
            showAlert(title: "Save Error", message: "Failed to save pinpoints: \(error.localizedDescription)")
        }
    }

    func createCustomCalloutView(for annotation: CustomAnnotation) -> UIView {
        let calloutView = UIView()
        calloutView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = annotation.subtitle
        subtitleLabel.font = UIFont.systemFont(ofSize: 14)
        subtitleLabel.numberOfLines = 0
        stackView.addArrangedSubview(subtitleLabel)

        let buttonsStackView = UIStackView()
        buttonsStackView.axis = .horizontal
        buttonsStackView.spacing = 10
        buttonsStackView.distribution = .fillEqually

        let renameButton = UIButton(type: .system)
        renameButton.setTitle("Rename", for: .normal)
        renameButton.tag = 1
        renameButton.addTarget(self, action: #selector(calloutButtonTapped(_:)), for: .touchUpInside)
        buttonsStackView.addArrangedSubview(renameButton)

        let deleteButton = UIButton(type: .system)
        deleteButton.setTitle("Delete", for: .normal)
        deleteButton.tag = 2
        deleteButton.addTarget(self, action: #selector(calloutButtonTapped(_:)), for: .touchUpInside)
        buttonsStackView.addArrangedSubview(deleteButton)

        if annotation.isCSV {
            let view3DButton = UIButton(type: .system)
            view3DButton.setTitle("3D View", for: .normal)
            view3DButton.tag = 3
            view3DButton.addTarget(self, action: #selector(calloutButtonTapped(_:)), for: .touchUpInside)
            buttonsStackView.addArrangedSubview(view3DButton)
        }

        stackView.addArrangedSubview(buttonsStackView)
        calloutView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: calloutView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: calloutView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: calloutView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: calloutView.bottomAnchor)
        ])

        return calloutView
    }

    @objc func calloutButtonTapped(_ sender: UIButton) {
        guard let annotation = mapView.selectedAnnotations.first as? CustomAnnotation else {
            return
        }

        switch sender.tag {
        case 1:
            presentRenameAlert(for: annotation)
        case 2:
            confirmDeletion(of: annotation)
        case 3:
            open3DView(for: annotation)
        default:
            break
        }
    }

    func presentRenameAlert(for annotation: CustomAnnotation) {
        let alert = UIAlertController(title: "Rename Annotation", message: "Enter a new name", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "New name"
            textField.text = annotation.title
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Rename", style: .default, handler: { _ in
            if let newName = alert.textFields?.first?.text, !newName.isEmpty {
                annotation.title = newName
                self.mapView.removeAnnotation(annotation)
                self.mapView.addAnnotation(annotation)
                self.savePinpointsToCSV()
            }
        }))
        present(alert, animated: true)
    }

    func renameAnnotation(_ annotation: CustomAnnotation, newName: String) {
        guard annotation.isCSV, let csvName = annotation.csvFileName else {
            annotation.title = newName
            mapView.removeAnnotation(annotation)
            mapView.addAnnotation(annotation)
            return
        }

        let docURL = getDocumentDirectory()
        let oldDBURL = docURL.appendingPathComponent(csvName + ".db")
        let oldCSVURL = docURL.appendingPathComponent(csvName + ".csv")

        let newDBURL = docURL.appendingPathComponent(newName + ".db")
        let newCSVURL = docURL.appendingPathComponent(newName + ".csv")

        do {
            if FileManager.default.fileExists(atPath: oldDBURL.path) {
                try? FileManager.default.removeItem(at: newDBURL)
                try FileManager.default.moveItem(at: oldDBURL, to: newDBURL)
            }

            if FileManager.default.fileExists(atPath: oldCSVURL.path) {
                try? FileManager.default.removeItem(at: newCSVURL)
                try FileManager.default.moveItem(at: oldCSVURL, to: newCSVURL)
            }

            annotation.title = newName
            annotation.csvFileName = newName
            mapView.removeAnnotation(annotation)
            mapView.addAnnotation(annotation)

            showAlert(title: "Renamed", message: "Data renamed to '\(newName)'")

        } catch {
            showAlert(title: "Error", message: "Failed to rename: \(error.localizedDescription)")
        }
    }

    func confirmDeletion(of annotation: CustomAnnotation) {
        let alert = UIAlertController(title: "Delete Annotation", message: "Are you sure you want to delete this annotation?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
            self.mapView.removeAnnotation(annotation)
            self.savePinpointsToCSV()
        }))
        present(alert, animated: true)
    }

    func deleteAnnotationData(_ annotation: CustomAnnotation) {
        if annotation.isCSV, let csvName = annotation.csvFileName {
            let docURL = getDocumentDirectory()
            let dbURL = docURL.appendingPathComponent(csvName + ".db")
            let csvURL = docURL.appendingPathComponent(csvName + ".csv")

            if FileManager.default.fileExists(atPath: dbURL.path) {
                try? FileManager.default.removeItem(at: dbURL)
            }
            if FileManager.default.fileExists(atPath: csvURL.path) {
                try? FileManager.default.removeItem(at: csvURL)
            }
        }

        mapView.removeAnnotation(annotation)
        showAlert(title: "Deleted", message: "Data has been deleted.")
    }

    func open3DView(for annotation: CustomAnnotation) {
        guard annotation.isCSV, let csvName = annotation.csvFileName else {
            showAlert(title: "Error", message: "No associated project found for 3D view.")
            return
        }

        let docURL = getDocumentDirectory()
        let dbURL = docURL.appendingPathComponent(csvName + ".db")

        if !FileManager.default.fileExists(atPath: dbURL.path) {
            showAlert(title: "Error", message: "Database file not found.")
            return
        }

        dismiss(animated: true) {
            if let window = UIApplication.shared.windows.first,
               let rootVC = window.rootViewController as? ViewController {
                rootVC.openDatabase(fileUrl: dbURL)
            } else {
                print("Cannot find ViewController to open database.")
            }
        }
    }

    func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }

    func loadAnnotationsFromCSV() {
        let documentsURL = getDocumentDirectory()
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            let csvFiles = fileURLs.filter { $0.pathExtension.lowercased() == "csv" }

            for fileURL in csvFiles {
                let baseFilename = fileURL.deletingPathExtension().lastPathComponent
                let dbFileURL = documentsURL.appendingPathComponent("\(baseFilename).db")
                if !FileManager.default.fileExists(atPath: dbFileURL.path) { continue }

                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                guard !lines.isEmpty else {
                    continue
                }

                let headerLine = lines[0]
                let headers = headerLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

                let projectIndex = headers.firstIndex(of: "project") ?? -1
                let nameIndex = headers.firstIndex(of: "name") ?? -1
                let latitudeIndex = headers.firstIndex(of: "latitude") ?? -1
                let longitudeIndex = headers.firstIndex(of: "longitude") ?? -1
                let altitudeIndex = headers.firstIndex(of: "altitude") ?? -1
                let volumeIndex = headers.firstIndex(of: "volume") ?? -1

                if latitudeIndex == -1 || longitudeIndex == -1 || altitudeIndex == -1 || volumeIndex == -1 {
                    continue
                }

                for line in lines[1...] {
                    let fields = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    guard fields.count >= headers.count else { continue }

                    guard let latitude = Double(fields[latitudeIndex]),
                          let longitude = Double(fields[longitudeIndex]),
                          let altitude = Double(fields[altitudeIndex]),
                          let volume = Double(fields[volumeIndex]) else { continue }

                    let project = projectIndex != -1 ? fields[projectIndex] : ""
                    let name = nameIndex != -1 ? fields[nameIndex] : baseFilename
                    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

                    let messageLines = [
                        "Project: \(project)",
                        "Name: \(name)",
                        String(format: "Latitude: %.6f", latitude),
                        String(format: "Longitude: %.6f", longitude),
                        String(format: "Altitude: %.2f m", altitude),
                        String(format: "Volume: %.3f m³", volume)
                    ]

                    let annotation = CustomAnnotation(
                        coordinate: coordinate,
                        title: name.isEmpty ? baseFilename : name,
                        subtitle: messageLines.joined(separator: "\n"),
                        isCSV: true,
                        csvFileName: baseFilename,
                        altitude: altitude,
                        project: project,
                        name: name,
                        volume: volume
                    )

                    mapView.addAnnotation(annotation)
                    let location = CLLocation(latitude: latitude, longitude: longitude)
                    geocoder.reverseGeocodeLocation(location) { [weak self, weak annotation] placemarks, error in
                        guard let self = self, let annotation = annotation else { return }
                        var addressStrings: [String] = []
                        if let placemark = placemarks?.first {
                            var addressString = ""
                            if let name = placemark.name { addressString += name }
                            if let thoroughfare = placemark.thoroughfare { addressString += " \(thoroughfare)" }
                            if let locality = placemark.locality { addressString += " \(locality)" }
                            if let administrativeArea = placemark.administrativeArea { addressString += " \(administrativeArea)" }
                            if let country = placemark.country { addressString += " \(country)" }

                            let updatedMessage = [
                                "Address: \(addressString)",
                                "Project: \(annotation.project ?? "")",
                                "Name: \(annotation.name ?? "")",
                                String(format: "Latitude: %.6f", annotation.coordinate.latitude),
                                String(format: "Longitude: %.6f", annotation.coordinate.longitude),
                                String(format: "Altitude: %.2f m", annotation.altitude ?? 0.0),
                                String(format: "Volume: %.3f m³", annotation.volume ?? 0.0),
                            ].joined(separator: "\n")

                            DispatchQueue.main.async {
                                annotation.subtitle = updatedMessage
                                if let view = self.mapView.view(for: annotation) {
                                    view.detailCalloutAccessoryView = self.createCustomCalloutView(for: annotation)
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error loading CSV files: \(error.localizedDescription)")
            showAlert(title: "CSV Load Error", message: error.localizedDescription)
        }
    }
}

// MARK: - MKMapViewDelegate
extension MapViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        }

        if let cluster = annotation as? MKClusterAnnotation {
            var clusterView = mapView.dequeueReusableAnnotationView(withIdentifier: "Cluster") as? MKMarkerAnnotationView
            if clusterView == nil {
                clusterView = MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: "Cluster")
                clusterView?.canShowCallout = true
            } else {
                clusterView?.annotation = cluster
            }

            let firstMember = cluster.memberAnnotations.first
            var clusterType: String = "mixed"

            if let firstAnnotation = firstMember as? CustomAnnotation {
                let isCSV = firstAnnotation.isCSV
                let allSameType = cluster.memberAnnotations.allSatisfy { ($0 as? CustomAnnotation)?.isCSV == isCSV }
                if allSameType {
                    clusterType = isCSV ? "csvCluster" : "pinpointCluster"
                }
            }

            if clusterType == "csvCluster" {
                clusterView?.markerTintColor = .systemBlue
                clusterView?.glyphImage = UIImage(systemName: "flag.fill")
            } else if clusterType == "pinpointCluster" {
                clusterView?.markerTintColor = .systemRed
                clusterView?.glyphImage = UIImage(systemName: "mappin")
            } else {
                clusterView?.markerTintColor = .gray
                clusterView?.glyphImage = UIImage(systemName: "questionmark")
            }

            clusterView?.glyphText = "\(cluster.memberAnnotations.count)"
            clusterView?.titleVisibility = .visible
            clusterView?.subtitleVisibility = .visible

            let titles = cluster.memberAnnotations.compactMap { ($0 as? CustomAnnotation)?.title }
            let uniqueTitles = Set(titles)
            let name = uniqueTitles.first ?? ""
            cluster.title = "\(name)"
            return clusterView
        }

        guard let customAnnotation = annotation as? CustomAnnotation else {
            return nil
        }

        let identifier = customAnnotation.isCSV ? "CSVAnnotation" : "UserAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: customAnnotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
        } else {
            annotationView?.annotation = customAnnotation
        }

        if customAnnotation.isCSV {
            annotationView?.markerTintColor = .systemBlue
            annotationView?.glyphImage = UIImage(systemName: "flag.fill")
            annotationView?.clusteringIdentifier = "csvCluster"
        } else {
            annotationView?.markerTintColor = .systemRed
            annotationView?.glyphImage = UIImage(systemName: "mappin")
            annotationView?.clusteringIdentifier = "pinpointCluster"
        }

        let calloutView = createCustomCalloutView(for: customAnnotation)
        annotationView?.detailCalloutAccessoryView = calloutView

        return annotationView
    }
}

// MARK: - UISearchBarDelegate
extension MapViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        if let query = searchBar.text, !query.isEmpty {
            searchCompleter.queryFragment = query
        }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            searchResults.removeAll()
            tableView.reloadData()
            tableView.isHidden = true
        } else {
            searchCompleter.queryFragment = searchText
        }
    }

    func searchForPlaces(query: String) {
        let annotations = mapView.annotations.filter {
            if let customAnnotation = $0 as? CustomAnnotation {
                return !customAnnotation.isCSV
            }
            return true
        }
        mapView.removeAnnotations(annotations)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = mapView.region

        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self else { return }

            if let error = error {
                print("Search failed: \(error.localizedDescription)")
                self.showAlert(title: "Search Failed", message: error.localizedDescription)
                return
            }

            guard let response = response, !response.mapItems.isEmpty else {
                self.showAlert(title: "Search Results", message: "No results found.")
                return
            }

            for item in response.mapItems {
                let annotation = MKPointAnnotation()
                annotation.title = item.name
                if let coordinate = item.placemark.location?.coordinate {
                    annotation.coordinate = coordinate
                }
                self.mapView.addAnnotation(annotation)
            }

            if let firstItem = response.mapItems.first, let coordinate = firstItem.placemark.location?.coordinate {
                self.mapView.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000), animated: true)
            }
        }
    }
}

// MARK: - MKLocalSearchCompleterDelegate
extension MapViewController: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results
        tableView.reloadData()
        tableView.isHidden = searchResults.isEmpty
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Autocomplete failed: \(error.localizedDescription)")
        showAlert(title: "Autocomplete Failed", message: error.localizedDescription)
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource
extension MapViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == self.tableView {
            return searchResults.count
        }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        if tableView == self.tableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
            let result = searchResults[indexPath.row]
            cell.textLabel?.text = result.title
            return cell
        }
        return UITableViewCell()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView == self.tableView {
            let completion = searchResults[indexPath.row]
            let searchRequest = MKLocalSearch.Request(completion: completion)
            let search = MKLocalSearch(request: searchRequest)
            search.start { [weak self] response, error in
                guard let self = self else { return }
                tableView.deselectRow(at: indexPath, animated: true)

                if let error = error {
                    print("Search failed: \(error.localizedDescription)")
                    self.showAlert(title: "Search Failed", message: error.localizedDescription)
                    return
                }

                guard let response = response, !response.mapItems.isEmpty else {
                    self.showAlert(title: "Search Results", message: "No results found.")
                    return
                }

                for item in response.mapItems {
                    if let coordinate = item.placemark.location?.coordinate {
                        self.createPinpoint(at: coordinate)
                    }
                }

                if let firstItem = response.mapItems.first,
                   let coordinate = firstItem.placemark.location?.coordinate {
                    self.mapView.setRegion(
                        MKCoordinateRegion(center: coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000),
                        animated: true
                    )
                }
                self.searchResults.removeAll()
                self.tableView.reloadData()
                self.tableView.isHidden = true
            }
        }
    }
}
