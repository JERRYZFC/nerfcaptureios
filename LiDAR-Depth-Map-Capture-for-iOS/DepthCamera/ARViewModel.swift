//
//  ARViewModel.swift
//  DepthCamera
//
//  Created by iori on 2024/11/27.
//

import ARKit
import UIKit
import tiff_ios

class ARViewModel: NSObject, ARSessionDelegate, ObservableObject {
    private var latestDepthMap: CVPixelBuffer?
    private var latestImage: CVPixelBuffer?
    @Published var processedDepthImage: UIImage?
    @Published var processedConfidenceImage: UIImage?
    @Published var showDepthMap: Bool = true
    @Published var showConfidenceMap: Bool = true
    @Published var captureSuccessful: Bool = false
    @Published var lastCapture: UIImage? = nil {
        didSet {
            print("lastCapture was set.")
        }
    }
    @Published var lastCaptureURL: URL?
    
    private var lastDepthUpdate: TimeInterval = 0
    private let depthUpdateInterval: TimeInterval = 0.1 // 10fps (1/10秒)
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestDepthMap = frame.sceneDepth?.depthMap
        latestImage = frame.capturedImage
        let currentTime = CACurrentMediaTime()
        
        if currentTime - lastDepthUpdate >= depthUpdateInterval {
            lastDepthUpdate = currentTime
            
            if showDepthMap, let depthMap = frame.sceneDepth?.depthMap {
                processDepthMap(depthMap)
            }

            if showConfidenceMap, let confidenceMap = frame.sceneDepth?.confidenceMap {
                processConfidenceMap(confidenceMap)
            }
        }
    }
    
    func saveCapture() {
        guard let depthMap = latestDepthMap, let image = latestImage else {
            print("Depth map or image is not available.")
            return
        }
        
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: Date())
        let dateDirURL = documentsDir.appendingPathComponent(dateString)
        
        do {
            try FileManager.default.createDirectory(at: dateDirURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create directory: \(error)")
            return
        }
        
        let timestamp = Date().timeIntervalSince1970
        let baseFilename = "\(timestamp)"
        let depthFileURL = dateDirURL.appendingPathComponent("\(baseFilename)_depth.tiff")
        let imageFileURL = dateDirURL.appendingPathComponent("\(baseFilename)_image.jpg")
        let visualDepthURL = dateDirURL.appendingPathComponent("\(baseFilename)_depth_visual.png")

        // Save raw float data, color image, and the new visualized depth map
        writeDepthMapToTIFF(depthMap: depthMap, url: depthFileURL)
        saveImage(image: image, url: imageFileURL)
        
        if let visualImage = createVisualDepthImage(from: depthMap), let pngData = visualImage.pngData() {
            do {
                try pngData.write(to: visualDepthURL)
                print("Visual depth map saved to \(visualDepthURL)")
            } catch {
                print("Failed to save visual depth map: \(error)")
            }
        }
        
        let uiImage = UIImage(ciImage: CIImage(cvPixelBuffer: image))
        
        DispatchQueue.main.async {
            self.lastCapture = uiImage
            self.lastCaptureURL = imageFileURL
            self.captureSuccessful = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.captureSuccessful = false
            }
        }
     
        print("Raw depth map saved to \(depthFileURL)")
        print("Image saved to \(imageFileURL)")
    }
    
    // MARK: - Private Image Processing and Saving
    
    private func processDepthMap(_ depthMap: CVPixelBuffer) {
        if let image = createVisualDepthImage(from: depthMap, rotate: true) {
            DispatchQueue.main.async { [weak self] in
                self?.processedDepthImage = image
            }
        }
    }

    private func createVisualDepthImage(from depthMap: CVPixelBuffer, rotate: Bool = false) -> UIImage? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        var normalizedData = [UInt8](repeating: 0, count: width * height * 4)

        let buffer = CVPixelBufferGetBaseAddress(depthMap)?.assumingMemoryBound(to: Float32.self)
        
        for y in 0..<height {
            for x in 0..<width {
                let depth = buffer?[y * width + x] ?? 0
                // Use the same normalization as the original preview logic
                let normalizedDepth = min(max(depth / 5.0, 0.0), 1.0)
                let pixel = UInt8(normalizedDepth * 255.0)
                
                let index = (y * width + x) * 4
                normalizedData[index] = pixel
                normalizedData[index + 1] = pixel
                normalizedData[index + 2] = pixel
                normalizedData[index + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(
            data: &normalizedData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ),
        let cgImage = context.makeImage() else { return nil }

        let finalImage = UIImage(cgImage: cgImage)
        if rotate {
            return finalImage.rotate(radians: .pi/2)
        }
        return finalImage
    }

    private func processConfidenceMap(_ confidenceMap: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }

        let width = CVPixelBufferGetWidth(confidenceMap)
        let height = CVPixelBufferGetHeight(confidenceMap)
        var rgbaData = [UInt8](repeating: 0, count: width * height * 4)

        let buffer = CVPixelBufferGetBaseAddress(confidenceMap)?.assumingMemoryBound(to: UInt8.self)
        
        for y in 0..<height {
            for x in 0..<width {
                let confidence = buffer?[y * width + x] ?? 0
                let index = (y * width + x) * 4
                
                switch confidence {
                case 0: rgbaData[index]=255; rgbaData[index+1]=0; rgbaData[index+2]=0
                case 1: rgbaData[index]=255; rgbaData[index+1]=255; rgbaData[index+2]=0
                case 2: rgbaData[index]=0; rgbaData[index+1]=255; rgbaData[index+2]=0
                default: rgbaData[index]=0; rgbaData[index+1]=0; rgbaData[index+2]=255
                }
                rgbaData[index + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(
            data: &rgbaData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ),
        let cgImage = context.makeImage() else { return }

        DispatchQueue.main.async { [weak self] in
            self?.processedConfidenceImage = UIImage(cgImage: cgImage).rotate(radians: .pi/2)
        }
    }
    
    private func writeDepthMapToTIFF(depthMap: CVPixelBuffer, url: URL) -> Bool {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return false }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        guard let rasters = TIFFRasters(width: Int32(width), andHeight: Int32(height), andSamplesPerPixel: 1, andSingleBitsPerSample: 32) else { return false }
        
        for y in 0..<height {
            let pixelBytes = baseAddress.advanced(by: y * bytesPerRow)
            let pixelBuffer = UnsafeBufferPointer<Float>(start: pixelBytes.assumingMemoryBound(to: Float.self), count: width)
            for x in 0..<width {
                rasters.setFirstPixelSampleAtX(Int32(x), andY: Int32(y), withValue: NSDecimalNumber(value: pixelBuffer[x]))
            }
        }
        
        let rowsPerStrip = UInt16(rasters.calculateRowsPerStrip(withPlanarConfiguration: Int32(TIFF_PLANAR_CONFIGURATION_CHUNKY)))
        
        guard let directory = TIFFFileDirectory() else { return false }
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
        
        guard let tiffImage = TIFFImage() else { return false }
        tiffImage.addFileDirectory(directory)
        
        TIFFWriter.writeTiff(withFile: url.path, andImage: tiffImage)
        return true
    }

    private func saveImage(image: CVPixelBuffer, url: URL) {
        let ciImage = CIImage(cvPixelBuffer: image)
        let context = CIContext()
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
           let jpegData = context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [:]) {
            do {
                try jpegData.write(to: url)
            } catch {
                print("Failed to save image: \(error)")
            }
        }
    }
}

extension UIImage {
    func rotate(radians: Float) -> UIImage? {
        var newSize = CGRect(origin: CGPoint.zero, size: self.size)
            .applying(CGAffineTransform(rotationAngle: CGFloat(radians)))
            .size
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)

        UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        context.translateBy(x: newSize.width/2, y: newSize.height/2)
        context.rotate(by: CGFloat(radians))
        
        let rect = CGRect(
            x: -self.size.width/2,
            y: -self.size.height/2,
            width: self.size.width,
            height: self.size.height)
        
        self.draw(in: rect)

        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage
    }
}
