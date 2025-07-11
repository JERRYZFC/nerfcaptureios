import Foundation
import ARKit
import Zip

class DatasetWriter {
    
    enum SessionState {
        case notStarted
        case started
    }
    
    private var manifest: Manifest
    private var projectName: String = ""
    private var projectDir: URL?
    private var imagesDir: URL?
    
    private var currentFrameCounter = 0
    @Published var writerState: SessionState = .notStarted
    
    init() {
        self.manifest = Manifest(
            cameraAngleX: 0,
            cameraAngleY: 0,
            flX: 0,
            flY: 0,
            cx: 0,
            cy: 0,
            w: 0,
            h: 0,
            frames: []
        )
    }

    func initializeProject() throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyMMdd_HHmmss"
        projectName = dateFormatter.string(from: Date())
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        projectDir = documentsDirectory.appendingPathComponent(projectName)
        
        guard let projectDir = projectDir else { return }
        
        if FileManager.default.fileExists(atPath: projectDir.path) {
            throw NSError(domain: "DatasetWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Project already exists"])
        }
        
        imagesDir = projectDir.appendingPathComponent("images")
        
        guard let imagesDir = imagesDir else { return }
        
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: nil)
        
        currentFrameCounter = 0
        writerState = .started
        print("Project initialized at: \(projectDir.path)")
    }
    
    func addFrame(frame: ARFrame) {
        guard writerState == .started, let imagesDir = imagesDir else { return }
        
        // 1. Set manifest properties on the first frame
        if manifest.w == 0 {
            manifest.w = Int(frame.camera.imageResolution.width)
            manifest.h = Int(frame.camera.imageResolution.height)
            manifest.flX = frame.camera.intrinsics[0, 0]
            manifest.flY = frame.camera.intrinsics[1, 1]
            manifest.cx = frame.camera.intrinsics[2, 0]
            manifest.cy = frame.camera.intrinsics[2, 1]
            manifest.cameraAngleX = 2 * atan(Float(manifest.w) / (2 * manifest.flX))
            manifest.cameraAngleY = 2 * atan(Float(manifest.h) / (2 * manifest.flY))
        }
        
        // 2. Prepare file paths
        let frameName = "\(currentFrameCounter)"
        let imageFileName = imagesDir.appendingPathComponent("\(frameName).jpg")
        let depthFileName = imagesDir.appendingPathComponent("\(frameName).depth.tiff")
        
        // 3. Get data
        let image = frame.capturedImage
        guard let depthMap = frame.sceneDepth?.depthMap else {
            print("Could not get depth map for frame \(currentFrameCounter)")
            return
        }
        
        // 4. Create Frame metadata
        let frameMetadata = Manifest.Frame(
            filePath: "images/\(frameName).jpg",
            depthPath: "images/\(frameName).depth.tiff",
            transformMatrix: arrayFromTransform(frame.camera.transform),
            timestamp: frame.timestamp
        )
        
        // 5. Write to disk asynchronously
        DispatchQueue.global(qos: .background).async {
            // Save RGB image
            self.saveImage(pixelBuffer: image, url: imageFileName)
            
            // Save Depth TIFF
            writeDepthMapToTIFFWithLibTIFF(depthMap: depthMap, url: depthFileName)
            
            DispatchQueue.main.async {
                self.manifest.frames.append(frameMetadata)
                self.currentFrameCounter += 1
            }
        }
    }
    
    func finalizeProject(zip: Bool = true) {
        guard writerState == .started, let projectDir = projectDir else { return }
        
        writerState = .notStarted
        
        let manifestPath = projectDir.appendingPathComponent("transforms.json")
        
        // Write manifest
        writeManifestToPath(path: manifestPath)
        
        // Zip and clean up
        DispatchQueue.global(qos: .background).async {
            do {
                if zip {
                    _ = try Zip.quickZipFiles([projectDir], fileName: self.projectName)
                    print("Project zipped to \(self.projectName).zip")
                }
                try FileManager.default.removeItem(at: projectDir)
                print("Cleaned up project directory.")
            } catch {
                print("Could not zip or clean up project: \(error)")
            }
        }
    }
    
    private func writeManifestToPath(path: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        do {
            let data = try encoder.encode(manifest)
            try data.write(to: path)
            print("Manifest file saved to: \(path.path)")
        } catch {
            print("Failed to write manifest file: \(error)")
        }
    }
    
    private func saveImage(pixelBuffer: CVPixelBuffer, url: URL) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let jpegData = context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9]) else {
            print("Failed to create JPEG data.")
            return
        }
        do {
            try jpegData.write(to: url)
        } catch {
            print("Failed to save image: \(error)")
        }
    }
    
    private func arrayFromTransform(_ transform: matrix_float4x4) -> [[Float]] {
        return [
            [transform.columns.0.x, transform.columns.1.x, transform.columns.2.x, transform.columns.3.x],
            [transform.columns.0.y, transform.columns.1.y, transform.columns.2.y, transform.columns.3.y],
            [transform.columns.0.z, transform.columns.1.z, transform.columns.2.z, transform.columns.3.z],
            [transform.columns.0.w, transform.columns.1.w, transform.columns.2.w, transform.columns.3.w]
        ]
    }
}
