//
// Copyright 2016 ESRI
//
// All rights reserved under the copyright laws of the United States
// and applicable international laws, treaties, and conventions.
//
// You may freely redistribute and use this sample code, with or
// without modification, provided you include the original copyright
// notice and use restrictions.
//
// See the use restrictions at http://help.arcgis.com/en/sdk/10.0/usageRestrictions.htm
//

import UIKit
import ArcGIS
import CoreMotion
import AVFoundation

class ViewController: UIViewController, CLLocationManagerDelegate, AGSGeoViewTouchDelegate {
    
    
    @IBOutlet weak var sceneView: AGSSceneView!
    var scene:AGSScene!
    var motionManager = CMMotionManager()
    var timer = Timer()
    let pi:Double = 3.14159
    let locationManager = CLLocationManager()
    var hasElevation:Bool = false
    var featureLayer:AGSFeatureLayer?
    let indicatorView = UIImageView(frame: CGRect(x: 0, y: 0, width: 18, height: 36))
    var indicatorPoint:AGSPoint?
    var selectedGeoElement:AGSGeoElement?
    var selectedAttachment:AGSAttachment?
    
    @IBOutlet var attachmentView: UIImageView!
    @IBOutlet var address1Label: UILabel!
    @IBOutlet var address2Label: UILabel!
    @IBOutlet var identifyView: UIView!
    @IBOutlet var nameLabel: UILabel!
    
    @IBOutlet var opacitySlider: UISlider!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //Create an instance of a map
        self.scene = AGSScene()
        
        //Define the basemap layer with ESRI imagery basemap
        self.scene.basemap = AGSBasemap.imagery()
        
        //Define the elevation source and surface
        let elevationSource = AGSArcGISTiledElevationSource(url: URL(string: "http://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer")!)
        let surface = AGSSurface()
        surface.elevationSources = [elevationSource]
        surface.name = "baseSurface"
        surface.isEnabled = true
        self.scene.baseSurface = surface
        
        //create the feature table and feature layer with our service
        let ft = AGSServiceFeatureTable(url: URL(string: "http://services2.arcgis.com/2B0gmGCMCH3iKkax/arcgis/rest/services/MinneapolisStPaulPOI/FeatureServer/0")!)
        self.featureLayer = AGSFeatureLayer(featureTable: ft)
        self.scene.operationalLayers.add(self.featureLayer!)

        self.sceneView.scene = self.scene
        self.sceneView.touchDelegate = self
        
        //set an initial viewpoint
        let vp = AGSViewpoint(latitude: 54, longitude: -114, scale: 1000000)
        self.sceneView.setViewpoint(vp)
        
        //set up location manager
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        
        // Set up the video preview view.
        previewView.session = session
        
        //
        // Check video authorization status. Video access is required and audio
        // access is optional. If audio access is denied, audio is not recorded
        // during movie recording.
        //
        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            // The user has not yet been presented with the option to grant
            // video access. We suspend the session queue to delay session
            // setup until the access request has completed.
            //
            // Note that audio access will be implicitly requested when we
            // create an AVCaptureDeviceInput for audio during session setup.
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { [unowned self] granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
                })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
        
        // Setup the capture session.
        // In general it is not safe to mutate an AVCaptureSession or any of its
        // inputs, outputs, or connections from multiple threads at the same time.
        //
        // Why not do all of this on the main queue?
        // Because AVCaptureSession.startRunning() is a blocking call which can
        // take a long time. We dispatch session setup to the sessionQueue so
        // that the main queue isn't blocked, which keeps the UI responsive.
        sessionQueue.async { [unowned self] in
            self.configureSession()
        }
        
        self.indicatorView.image = #imageLiteral(resourceName: "Pin.png")
        self.view.addSubview(self.indicatorView)
        self.indicatorView.isHidden = true;
        self.view.bringSubview(toFront: self.identifyView)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.startDeviceMotion()
        
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("Hey, What's That? doesn't have permission to use the camera, please change privacy settings", comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "Hey, What's That?", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .`default`, handler: { action in
                        UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "Hey, What's That?", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        self.stopDeviceMotion()
        
        sessionQueue.async { [unowned self] in
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    //change the opacity of the sceneView
    @IBAction func opacityChanged(_ sender: Any) {
        self.sceneView.alpha = CGFloat(self.opacitySlider.value)
    }
    
    // MARK: Device Motion and Location 
    
    func startDeviceMotion() {
        
        //create a timer to grab motion updates every 0.5 seconds
        self.timer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(ViewController.updateDeviceMotion), userInfo: nil, repeats: true)
        
        //create and setup the motion manager
        self.motionManager = CMMotionManager()
        motionManager.showsDeviceMovementDisplay = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xTrueNorthZVertical)
        
        //tell the location manager to start updating the information we need
        self.locationManager.startUpdatingHeading()
        self.locationManager.startUpdatingLocation()
    }
    
    func stopDeviceMotion() {
        self.timer = Timer()
        self.motionManager.stopDeviceMotionUpdates()
        self.locationManager.stopUpdatingHeading()
        self.locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        //new heading
        let currentCamera = self.sceneView.currentViewpointCamera()
        let camera = currentCamera.rotate(toHeading: newHeading.trueHeading - 90, pitch: currentCamera.pitch, roll: currentCamera.roll)
        self.sceneView.setViewpointCamera(camera);
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        let location = locations[locations.count - 1]
        var locationPoint = AGSPoint(clLocationCoordinate2D: location.coordinate)
        let pointBuilder = locationPoint.toBuilder()

        //
        //need to set the elevation based on our surface elevation at "locationPoint"
        //
        //but...this is throwing an exception; not sure if it's an issue with the Cocoa SDK or C_API
        //
//        if (!self.hasElevation && self.sceneView.scene?.loadStatus == .loaded) {
//            self.sceneView.scene?.baseSurface?.elevation(for: locationPoint, completion: { (elevation, error) in
//                pointBuilder.z = elevation
//                print("Elevation = \(elevation)")
//                locationPoint = pointBuilder.toGeometry()
//                
//                let camera = self.sceneView.currentViewpointCamera().move(toLocation: locationPoint)
//                self.sceneView.setViewpointCamera(camera);
//                
//                self.hasElevation = true
//            })
//        }
        
        //hack around above exception:
        pointBuilder.z = 10
        
        locationPoint = pointBuilder.toGeometry()
        
        let camera = self.sceneView.currentViewpointCamera().move(toLocation: locationPoint)
        self.sceneView.setViewpointCamera(camera);

        //udpate location of indicator view
        self.indicatorView.isHidden = !self.updateIndicatorView()
    }
    
    func updateDeviceMotion() {
        if let update = self.motionManager.deviceMotion {
            
            //grab roll value and update for our coordinate system
            var roll = update.attitude.roll
            roll = fabs(roll) / self.pi * 180
            
            //get current camera
            let currentCamera = self.sceneView.currentViewpointCamera()
            
            //sice we're always in landscape mode, the devicemotion.roll is actually the camera pitch
            let camera = currentCamera.rotate(toHeading: currentCamera.heading, pitch: roll, roll: currentCamera.roll)
            self.sceneView.setViewpointCamera(camera);
            
            //udpate location of indicator view
            self.indicatorView.isHidden = !self.updateIndicatorView()
        }
    }
    
    // MARK: GeoView Touch Delegate methods
    
    func geoView(_ geoView: AGSGeoView, didTapAtScreenPoint screenPoint: CGPoint, mapPoint: AGSPoint) {
        //identify
        geoView.identifyLayer(self.featureLayer!, screenPoint: screenPoint, tolerance: 10, returnPopupsOnly: false, completion: { (result) in

            //get result cound and reset some values
            let resultCount = result.geoElements.count
            self.identifyView.isHidden = (resultCount == 0)
            self.indicatorView.isHidden = (resultCount == 0)
            self.indicatorPoint = nil
            self.selectedGeoElement = nil
            self.attachmentView.image = nil

            if resultCount > 0 {
                //we have results; grab and use first result only
                let geoElement = result.geoElements[0]
                
                //fill fields in identify view
                self.nameLabel.text = geoElement.attributes.object(forKey: "Name") as? String
                self.address1Label.text = geoElement.attributes.object(forKey: "Address") as? String
                self.address2Label.text = geoElement.attributes.object(forKey: "Address2") as? String
                
                //hold onto geoElement so we can fetch the attachments
                self.selectedGeoElement = geoElement
                if geoElement is AGSArcGISFeature {
                    let feature = geoElement as! AGSArcGISFeature
                    feature.fetchAttachments(completion: { (attachments, error) in
                        if attachments != nil && (attachments?.count)! > 0 {
                            
                            if let attachment = attachments?[0] {
                                if (attachment.contentType == "image/jpg"    ||
                                    attachment.contentType == "image/jpeg"   ||
                                    attachment.contentType == "image/pjpeg"  ||
                                    attachment.contentType == "image/png"    ||
                                    attachment.contentType == "image/gif"    ||
                                    attachment.contentType == "image/tiff") {
                                    
                                    //hold onto the attachment so we can fetch the it's data
                                    self.selectedAttachment = attachment
                                    attachment.fetchData(completion: { (data, error) in
                                        if data != nil {
                                            //create and set attachment image
                                            let attachmentImage = UIImage(data: data!)
                                            self.attachmentView.image = attachmentImage
                                        }
                                    })
                                }
                            }
                        }
                    })
                }
                else {
                    self.attachmentView.image = nil
                }
                
                //set up indicator
                self.indicatorPoint = geoElement.geometry as? AGSPoint
                self.indicatorView.isHidden = !self.updateIndicatorView()
            }
        })
    }
    
    func updateIndicatorView() -> Bool {
        //this will return true if the indicator should be shown
        if let point = self.indicatorPoint {
            let locationToScreenResult = self.sceneView.location(toScreen: point)
            if (locationToScreenResult.visibility != .notOnScreen) {
                //show indicator if we're not off the screen
                self.indicatorView.frame = CGRect(x: locationToScreenResult.screenPoint.x - 9.0,
                                                  y: locationToScreenResult.screenPoint.y - 36, width: 18, height: 36)
                return true
            }
        }
        return false
    }
    
    // MARK: Session Management
    
    fileprivate enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    fileprivate let session = AVCaptureSession()
    
    fileprivate var isSessionRunning = false
    
    fileprivate let sessionQueue = DispatchQueue(label: "session queue", attributes: [], target: nil) // Communicate with the session and other session objects on this queue.
    
    fileprivate var setupResult: SessionSetupResult = .success
    
    var videoDeviceInput: AVCaptureDeviceInput!
    
    @IBOutlet fileprivate weak var previewView: PreviewView!
    
    // Call this on the session queue.
    fileprivate func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        // We do not create an AVCaptureMovieFileOutput when setting up the session because the
        // AVCaptureMovieFileOutput does not support movie recording with AVCaptureSessionPresetPhoto.
        session.sessionPreset = AVCaptureSessionPresetHigh
        
        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            // Choose the back dual camera if available, otherwise default to a wide angle camera.
            if let dualCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInDuoCamera, mediaType: AVMediaTypeVideo, position: .back) {
                defaultVideoDevice = dualCameraDevice
            }
            else if let backCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .back) {
                // If the back dual camera is not available, default to the back wide angle camera.
                defaultVideoDevice = backCameraDevice
            }
            else if let frontCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .front) {
                // In some cases where users break their phones, the back wide angle camera is not available. In this case, we should default to the front wide angle camera.
                defaultVideoDevice = frontCameraDevice
            }
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    self.previewView.videoPreviewLayer.connection.videoOrientation = .landscapeLeft
                }
            }
            else {
                print("Could not add video device input to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        }
        catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
}

