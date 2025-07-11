import Foundation
import ARKit
import tiff_ios

class DatasetWriter {
    private var projectURL: URL!
    private var imagesURL: URL!
    private var manifest: Manifest!
    private var frameCount = 0

    func initializeProject() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss"
        let timestamp = formatter.string(from: Date())
        
        projectURL = documentsURL.appendingPathComponent(timestamp)
        imagesURL = projectURL.appendingPathComponent("rgb") // Match SplaTAM's expected directory name
        
        do {
            try fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: nil)
            print("Project directory created at: \(projectURL.path)")
        } catch {
            print("Error creating project directory: \(error)")
        }
        
        manifest = nil
    }

    func addFrame(frame: ARFrame) {
        let image = frame.capturedImage
        guard let depthMap = frame.sceneDepth?.depthMap,
              let depthPathURL = frame.sceneDepth?.depthMap else { return }

        if manifest == nil {
            let intrinsics = frame.camera.intrinsics
            let imageResolution = frame.camera.imageResolution
            manifest = Manifest(
                flX: intrinsics[0, 0],
                flY: intrinsics[1, 1],
                cX: intrinsics[2, 0],
                cY: intrinsics[2, 1],
                w: Int(imageResolution.width),
                h: Int(imageResolution.height),
                integerDepthScale: 1000.0 / 65535.0, // Standard scale for SplaTAM
                frames: []
            )
        }
        
        let imagePath = "rgb/\(frameCount).jpg"
        let depthPath = "depth/\(frameCount).tiff"
        
        // Create depth directory if it doesn't exist
        let depthDirURL = projectURL.appendingPathComponent("depth")
        if !FileManager.default.fileExists(atPath: depthDirURL.path) {
            try? FileManager.default.createDirectory(at: depthDirURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        let imageURL = projectURL.appendingPathComponent(imagePath)
        let depthURL = projectURL.appendingPathComponent(depthPath)
        
        // Save RGB image
        saveImage(pixelBuffer: image, to: imageURL)
        
        // Save depth data as 32-bit float TIFF
        writeDepthMapToTIFF(depthMap: depthMap, url: depthURL)
        
        // Get transform matrix
        let transformMatrix = frame.camera.transform.toFloat4x4()
        
        let frameData = Frame(
            filePath: imagePath,
            depthPath: depthPath,
            transformMatrix: transformMatrix
        )
        
        manifest.frames.append(frameData)
        frameCount += 1
    }

    func finalizeProject() {
        guard manifest != nil else {
            print("Manifest is nil, cannot finalize project.")
            return
        }
        
        let transformsURL = projectURL.appendingPathComponent("transforms.json")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let jsonData = try encoder.encode(manifest)
            try jsonData.write(to: transformsURL)
            print("transforms.json saved successfully.")
        } catch {
            print("Error writing transforms.json: \(error)")
        }
        
        // Reset for next recording
        frameCount = 0
        manifest = nil
        projectURL = nil
        imagesURL = nil
    }

    // MARK: - Private Helper Functions

    private func saveImage(pixelBuffer: CVPixelBuffer, to url: URL) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let jpegData = context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [:]) else {
            print("Failed to create JPEG data.")
            return
        }
        
        do {
            try jpegData.write(to: url)
        } catch {
            print("Error saving image to \(url.path): \(error)")
        }
    }

    private func writeDepthMapToTIFF(depthMap: CVPixelBuffer, url: URL) {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }
        
        guard let rasters = TIFFRasters(width: Int32(width), andHeight: Int32(height), andSamplesPerPixel: 1, andSingleBitsPerSample: 32) else { return }
        
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
        for y in 0..<height {
            for x in 0..<width {
                let value = floatBuffer[y * width + x]
                rasters.setFirstPixelSampleAtX(Int32(x), andY: Int32(y), withValue: NSDecimalNumber(value: value))
            }
        }
        
        let rowsPerStrip = UInt16(rasters.calculateRowsPerStrip(withPlanarConfiguration: Int32(TIFF_PLANAR_CONFIGURATION_CHUNKY)))
        
        guard let directory = TIFFFileDirectory() else { return }
        directory.setImageWidth(UInt16(width))
        directory.setImageHeight(UInt16(height))
        directory.setBitsPerSampleAsSingleValue(32)
        directory.setCompression(UInt16(TIFF_COMPRESSION_NO))
        directory.setPhotometricInterpretation(UInt16(TIFF_PHOTOMETRIC_INTERPRETATION_BLACK_IS_ZERO))
        directory.setSamplesPerPixel(1)
        directory.setRowsPerStrip(rowsPerStrip)
        directory.setPlanarConfiguration(UInt16(TIFF_PLANAR_CONFIGURATION_CHUNKY))
        directory.setSampleFormatAsSingleValue(UInt16(TIFF_SAMPLE_FORMAT_FLOAT))
        directory.writeRasters = rasters
        
        guard let tiffImage = TIFFImage() else { return }
        tiffImage.addFileDirectory(directory)
        
        TIFFWriter.writeTiff(withFile: url.path, andImage: tiffImage)
    }
}

extension simd_float4x4 {
    func toFloat4x4() -> [[Float]] {
        return [
            [columns.0.x, columns.1.x, columns.2.x, columns.3.x],
            [columns.0.y, columns.1.y, columns.2.y, columns.3.y],
            [columns.0.z, columns.1.z, columns.2.z, columns.3.z],
            [columns.0.w, columns.1.w, columns.2.w, columns.3.w]
        ]
    }
}
