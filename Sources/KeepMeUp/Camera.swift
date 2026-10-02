import AVFoundation
import Foundation

final class Camera: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    static let shared = Camera()

    private let queue = DispatchQueue(label: "com.amirhp.KeepMeUp.camera")
    private var session: AVCaptureSession?
    private var output: AVCapturePhotoOutput?
    private var completion: ((Result<URL, Error>) -> Void)?

    enum CameraError: LocalizedError {
        case denied
        case noDevice
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied: return "Camera access is off. Allow KeepMeUp in System Settings → Privacy & Security → Camera."
            case .noDevice: return "No camera was found on this Mac."
            case .failed(let text): return text
            }
        }
    }

    func snapshot() async -> Result<URL, Error> {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { return .failure(CameraError.denied) }
        } else if status == .denied || status == .restricted {
            return .failure(CameraError.denied)
        }
        return await withCheckedContinuation { continuation in
            queue.async { self.capture { continuation.resume(returning: $0) } }
        }
    }

    private func capture(_ done: @escaping (Result<URL, Error>) -> Void) {
        guard let device = AVCaptureDevice.default(for: .video) else {
            done(.failure(CameraError.noDevice))
            return
        }
        let session = AVCaptureSession()
        session.sessionPreset = .photo
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CameraError.failed("Camera is in use by another app") }
            session.addInput(input)
            let output = AVCapturePhotoOutput()
            guard session.canAddOutput(output) else { throw CameraError.failed("Couldn't set up capture") }
            session.addOutput(output)
            self.session = session
            self.output = output
            self.completion = done
            session.startRunning()
            queue.asyncAfter(deadline: .now() + 0.6) {
                guard self.completion != nil else { return }
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        } catch {
            done(.failure(error))
            teardown()
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { teardown() }
        guard let done = completion else { return }
        completion = nil
        if let error {
            done(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            done(.failure(CameraError.failed("The camera returned no image")))
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KeepMeUp", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("camera-\(Int(Date().timeIntervalSince1970)).jpg")
        do {
            try data.write(to: url)
            done(.success(url))
        } catch {
            done(.failure(error))
        }
    }

    private func teardown() {
        session?.stopRunning()
        session = nil
        output = nil
    }
}
