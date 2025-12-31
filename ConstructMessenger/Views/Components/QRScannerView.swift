//
//  QRScannerView.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 30.12.2025.
//

import SwiftUI
import AVFoundation

struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onCodeScanned: (String) -> Void

    @StateObject private var scanner = QRCodeScanner()
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera preview
                QRCodeScannerViewRepresentable(scanner: scanner)
                    .ignoresSafeArea()

                // Overlay with scanning frame
                VStack {
                    Spacer()

                    VStack(spacing: 16) {
                        Text("Scan QR Code")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Position the QR code within the frame")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                    .padding(.bottom, 60)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                scanner.startScanning()
            }
            .onDisappear {
                scanner.stopScanning()
            }
            .onChange(of: scanner.scannedCode) { newValue in
                if let code = newValue {
                    handleScannedCode(code)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        scanner.stopScanning()

        // Validate it's a construct:// URL
        if code.hasPrefix("construct://add-contact") {
            onCodeScanned(code)
        } else {
            errorMessage = "Invalid QR code. Please scan a Construct Messenger contact code."
            showingError = true
        }
    }
}

// MARK: - QR Code Scanner Logic
class QRCodeScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var scannedCode: String?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    func startScanning() {
        captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        if captureSession?.canAddInput(videoInput) == true {
            captureSession?.addInput(videoInput)
        } else {
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession?.canAddOutput(metadataOutput) == true {
            captureSession?.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    func stopScanning() {
        captureSession?.stopRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }

            // Only trigger once
            if scannedCode == nil {
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                scannedCode = stringValue
            }
        }
    }

    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        guard let captureSession = captureSession else { return nil }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill

        return previewLayer
    }
}

// MARK: - UIViewRepresentable for Camera Preview
struct QRCodeScannerViewRepresentable: UIViewRepresentable {
    @ObservedObject var scanner: QRCodeScanner

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        // Store the view in coordinator so we can add the layer later
        context.coordinator.parentView = view

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Add preview layer if it's available and not already added
        if context.coordinator.previewLayer == nil,
           let previewLayer = scanner.getPreviewLayer() {
            previewLayer.frame = uiView.bounds
            uiView.layer.insertSublayer(previewLayer, at: 0)
            context.coordinator.previewLayer = previewLayer
        }

        // Update preview layer frame when view size changes
        if let previewLayer = context.coordinator.previewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
        var parentView: UIView?
    }
}

#Preview {
    QRScannerView { code in
        print("Scanned: \(code)")
    }
}
