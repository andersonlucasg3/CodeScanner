//
//  CodeScannerView.swift
//
//  Created by Paul Hudson on 10/12/2019.
//  Copyright © 2019 Paul Hudson. All rights reserved.
//

import AVFoundation
import SwiftUI

/// A SwiftUI view that is able to scan barcodes, QR codes, and more, and send back what was found.
/// To use, set `codeTypes` to be an array of things to scan for, e.g. `[.qr]`, and set `completion` to
/// a closure that will be called when scanning has finished. This will be sent the string that was detected or a `ScanError`.
/// For testing inside the simulator, set the `simulatedData` property to some test data you want to send back.
public struct CodeScannerView: UIViewControllerRepresentable {
    public enum ScanError: Error {
        case badInput, badOutput
    }

    public class ScannerCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: CodeScannerView
        var scanInterval: Double = 2.0
        var lastTime = Date(timeIntervalSince1970: 0)

        init(parent: CodeScannerView) {
            self.parent = parent
        }

        public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            if let metadataObject = metadataObjects.first {
                guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
                guard let stringValue = readableObject.stringValue else { return }
                foundCode(code: stringValue)
            }
        }
        
        func foundCode(code: String) {
            let now = Date()
            if now.timeIntervalSince(self.lastTime) >= self.scanInterval {
                self.lastTime = now
                self.found(code: code)
            }
        }

        func found(code: String) {
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            self.parent.completion(.success(code))
        }

        func didFail(reason: ScanError) {
            self.parent.completion(.failure(reason))
        }
    }

    #if targetEnvironment(simulator)
    public class ScannerViewController: UIViewController,UIImagePickerControllerDelegate,UINavigationControllerDelegate{
        var delegate: ScannerCoordinator?
        override public func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = true
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 0

            label.text = "You're running in the simulator, which means the camera isn't available. Tap anywhere to send back some simulated data."
            label.textAlignment = .center
            let button = UIButton()
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle("Or tap here to select a custom image", for: .normal)
            button.setTitleColor(UIColor.systemBlue, for: .normal)
            button.setTitleColor(UIColor.gray, for: .highlighted)
            button.addTarget(self, action: #selector(self.openGallery), for: .touchUpInside)

            let stackView = UIStackView()
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.axis = .vertical
            stackView.spacing = 50
            stackView.addArrangedSubview(label)
            stackView.addArrangedSubview(button)

            view.addSubview(stackView)

            NSLayoutConstraint.activate([
                button.heightAnchor.constraint(equalToConstant: 50),
                stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
                stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }

        override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let simulatedData = delegate?.parent.simulatedData else {
                print("Simulated Data Not Provided!")
                return
            }

            delegate?.found(code: simulatedData)
        }

        @objc func openGallery(_ sender: UIButton){
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            self.present(imagePicker, animated: true, completion: nil)
        }

        public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]){
            if let qrcodeImg = info[.originalImage] as? UIImage {
                let detector:CIDetector=CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy:CIDetectorAccuracyHigh])!
                let ciImage:CIImage=CIImage(image:qrcodeImg)!
                var qrCodeLink=""

                let features=detector.features(in: ciImage)
                for feature in features as! [CIQRCodeFeature] {
                    qrCodeLink += feature.messageString!
                }

                if qrCodeLink=="" {
                    delegate?.didFail(reason: .badOutput)
                }else{
                    delegate?.found(code: qrCodeLink)
                }
            }
            else{
                print("Something went wrong")
            }
            self.dismiss(animated: true, completion: nil)
        }
    }
    #else
    public class ScannerViewController: UIViewController {
        var captureSession: AVCaptureSession!
        var previewLayer: AVCaptureVideoPreviewLayer!
        var delegate: ScannerCoordinator?
        
        private var regionOfInterestView: UIView!
        private var cropRegionView: UIView!
        private var metadataOutput: AVCaptureMetadataOutput?

        override public func viewDidLoad() {
            super.viewDidLoad()


            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(updateOrientation),
                                                   name: Notification.Name("UIDeviceOrientationDidChangeNotification"),
                                                   object: nil)

            view.backgroundColor = UIColor.black
            captureSession = AVCaptureSession()

            guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
            let videoInput: AVCaptureDeviceInput

            do {
                videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            } catch {
                return
            }

            if (captureSession.canAddInput(videoInput)) {
                captureSession.addInput(videoInput)
            } else {
                delegate?.didFail(reason: .badInput)
                return
            }

            self.metadataOutput = AVCaptureMetadataOutput()

            if (captureSession.canAddOutput(self.metadataOutput!)) {
                captureSession.addOutput(self.metadataOutput!)

                self.metadataOutput?.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
                self.metadataOutput?.metadataObjectTypes = delegate?.parent.codeTypes
            } else {
                delegate?.didFail(reason: .badOutput)
                return
            }
        }

        override public func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            
            self.previewLayer?.frame = view.layer.bounds
        }
        
        public override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            
            guard let regionOfInterestView = self.regionOfInterestView else { return }
            regionOfInterestView.frame = self.calculateFrame()
            regionOfInterestView.center = self.view.center
            self.metadataOutput?.rectOfInterest = self.previewLayer.metadataOutputRectConverted(fromLayerRect: regionOfInterestView.frame)
            self.updateOrientation()
            self.captureSession.commitConfiguration()
        }

        @objc func updateOrientation() {
            guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else { return }
            guard let connection = captureSession.connections.last, connection.isVideoOrientationSupported else { return }
            connection.videoOrientation = AVCaptureVideoOrientation(rawValue: orientation.rawValue) ?? .portrait
        }

        override public func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
            self.previewLayer.frame = self.view.layer.bounds
            self.previewLayer.videoGravity = .resizeAspectFill
            self.view.layer.addSublayer(self.previewLayer)
            self.updateOrientation()
            
            self.regionOfInterestView = UIView.init(frame: self.calculateFrame())
            self.regionOfInterestView.layer.borderWidth = 4
            self.regionOfInterestView.layer.borderColor = UIColor.lightGray.cgColor
            self.regionOfInterestView.center = view.center
            self.view.addSubview(self.regionOfInterestView)
            
            self.cropRegionView = UIView.init(frame: self.view.bounds)
            self.cropRegionView.center = self.view.center
            self.cropRegionView.backgroundColor = UIColor.init(white: 0, alpha: 0.5)
            self.setMask(with: self.regionOfInterestView.frame, in: self.cropRegionView)
            self.view.addSubview(self.cropRegionView)
            
            self.metadataOutput?.rectOfInterest = self.previewLayer.metadataOutputRectConverted(fromLayerRect: self.regionOfInterestView.frame)
            
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }

        override public func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            
            if (captureSession?.isRunning == false) {
                captureSession.startRunning()
            }
        }

        override public func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)

            if (captureSession?.isRunning == true) {
                captureSession.stopRunning()
            }
            
            self.regionOfInterestView?.removeFromSuperview()

            NotificationCenter.default.removeObserver(self)
        }

        override public var prefersStatusBarHidden: Bool {
            return true
        }

        override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            return .all
        }
        
        private func calculateFrame() -> CGRect {
            if UIDevice.current.orientation.isLandscape {
                return CGRect.init(x: 0, y: 0,
                            width: UIScreen.main.bounds.height * 0.8,
                            height: UIScreen.main.bounds.height * 0.4)
            } else {
                return CGRect.init(x: 0, y: 0,
                            width: UIScreen.main.bounds.width * 0.8,
                            height: UIScreen.main.bounds.width * 0.4)
            }
        }
        
        func setMask(with hole: CGRect, in view: UIView){

            // Create a mutable path and add a rectangle that will be h
            let mutablePath = CGMutablePath()
            mutablePath.addRect(view.bounds)
            mutablePath.addRect(hole)

            // Create a shape layer and cut out the intersection
            let mask = CAShapeLayer()
            mask.path = mutablePath
            mask.fillRule = .evenOdd

            // Add the mask to the view
            view.layer.mask = mask
        }
    }
    #endif

    public let codeTypes: [AVMetadataObject.ObjectType]
    public var simulatedData = ""
    public var completion: (Result<String, ScanError>) -> Void

    public init(codeTypes: [AVMetadataObject.ObjectType], simulatedData: String = "", completion: @escaping (Result<String, ScanError>) -> Void) {
        self.codeTypes = codeTypes
        self.simulatedData = simulatedData
        self.completion = completion
    }

    public func makeCoordinator() -> ScannerCoordinator {
        return ScannerCoordinator(parent: self)
    }

    public func makeUIViewController(context: Context) -> ScannerViewController {
        let viewController = ScannerViewController()
        viewController.delegate = context.coordinator
        return viewController
    }

    public func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {

    }
}
