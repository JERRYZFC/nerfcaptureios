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
    @Published var processedDepthImage: UIImage?
    @Published var processedConfidenceImage: UIImage?
    @Published var showDepthMap: Bool = true
    @Published var showConfidenceMap: Bool = true
    @Published var isRecording: Bool = false
    private var datasetWriter: DatasetWriter?
    
    private var lastDepthUpdate: TimeInterval = 0
    private let depthUpdateInterval: TimeInterval = 0.1 // 10fps (1/10秒)
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let currentTime = CACurrentMediaTime()
        if currentTime - lastDepthUpdate < depthUpdateInterval {
            return
        }
        lastDepthUpdate = currentTime

        if isRecording {
            datasetWriter?.addFrame(frame: frame)
        }

        // Update previews
        if showDepthMap, let depthMap = frame.sceneDepth?.depthMap {
            processDepthMap(depthMap)
        }
        if showConfidenceMap, let confidenceMap = frame.sceneDepth?.confidenceMap {
            processConfidenceMap(confidenceMap)
        }
    }

    func startRecording() {
        datasetWriter = DatasetWriter()
        datasetWriter?.initializeProject()
        isRecording = true
    }

    func stopRecording() {
        datasetWriter?.finalizeProject()
        datasetWriter = nil
        isRecording = false
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
