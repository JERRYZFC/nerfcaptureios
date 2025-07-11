//
//  DepthMapDetailView.swift
//  DepthCamera
//
//  Created by Assistant on 2025/01/07.
//

import SwiftUI
import CoreGraphics
import tiff_ios

struct DepthMapDetailView: View {
    let depthURL: URL
    @Environment(\.dismiss) var dismiss
    @State private var depthImage: UIImage?
    @State private var tapLocation: CGPoint = .zero
    @State private var depthValue: Float?
    @State private var showCrosshair = false
    @State private var imageSize: CGSize = .zero
    @State private var depthData: [[Float]] = []
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                GeometryReader { geometry in
                    if let depthImage = depthImage {
                        ZStack {
                            // Depth画像
                            Image(uiImage: depthImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .background(
                                    GeometryReader { imageGeometry in
                                        Color.clear.onAppear {
                                            imageSize = imageGeometry.size
                                        }
                                    }
                                )
                                .onTapGesture { location in
                                    tapLocation = location
                                    showCrosshair = true
                                    updateDepthValue(at: location, in: geometry.size)
                                }
                            
                            // クロスヘア表示
                            if showCrosshair {
                                CrosshairView(location: tapLocation)
                            }
                        }
                    } else {
                        ProgressView("Loading depth map...")
                            .foregroundColor(.white)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                
                // Depth値表示
                if let depth = depthValue {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 8) {
                                Text("Depth Distance")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(String(format: "%.3f m", depth))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                                    )
                            )
                            .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Depth Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                loadDepthData()
            }
        }
    }
    
    private func loadDepthData() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let tiffImage = TIFFReader.readTiff(fromFile: depthURL.path),
                  let directory = tiffImage.fileDirectory(),
                  let rasters = directory.readRasters() else {
                print("Failed to read TIFF file at \(depthURL.path)")
                return
            }
            
            let width = Int(rasters.width)
            let height = Int(rasters.height)
            var loadedDepthData = Array(repeating: Array(repeating: Float(0), count: width), count: height)
            
            // Read the raw float values from the TIFF file
            for y in 0..<height {
                for x in 0..<width {
                    if let value = rasters.pixelSample(atX: Int32(x), andY: Int32(y))?.floatValue {
                        loadedDepthData[y][x] = value
                    }
                }
            }
            
            // Create a high-contrast visual representation for the preview
            let visualImage = createVisualDepthImage(from: loadedDepthData, width: width, height: height)
            
            DispatchQueue.main.async {
                self.depthData = loadedDepthData
                self.depthImage = visualImage
            }
        }
    }
    
    private func createVisualDepthImage(from data: [[Float]], width: Int, height: Int) -> UIImage? {
        var normalizedData = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let depth = data[y][x]
                // Normalize to 0-5m range for consistent, high-contrast visualization
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

        return UIImage(cgImage: cgImage)
    }
    
    private func updateDepthValue(at location: CGPoint, in viewSize: CGSize) {
        guard let image = depthImage, !depthData.isEmpty else { return }
        
        let imageAspectRatio = image.size.width / image.size.height
        let viewAspectRatio = viewSize.width / viewSize.height
        
        var imageFrame: CGRect
        if imageAspectRatio > viewAspectRatio {
            let height = viewSize.width / imageAspectRatio
            imageFrame = CGRect(x: 0, y: (viewSize.height - height) / 2, width: viewSize.width, height: height)
        } else {
            let width = viewSize.height * imageAspectRatio
            imageFrame = CGRect(x: (viewSize.width - width) / 2, y: 0, width: width, height: viewSize.height)
        }
        
        guard imageFrame.contains(location) else {
            self.depthValue = nil
            return
        }
        
        let normalizedX = (location.x - imageFrame.origin.x) / imageFrame.width
        let normalizedY = (location.y - imageFrame.origin.y) / imageFrame.height
        
        let pixelX = Int(normalizedX * CGFloat(depthData[0].count))
        let pixelY = Int(normalizedY * CGFloat(depthData.count))
        
        guard pixelY >= 0, pixelY < depthData.count,
              pixelX >= 0, pixelX < depthData[pixelY].count else {
            return
        }
        
        depthValue = depthData[pixelY][pixelX]
    }
}

struct CrosshairView: View {
    let location: CGPoint
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 40, height: 1)
                .position(location)
            
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 1, height: 40)
                .position(location)
            
            Circle()
                .fill(Color.clear)
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 12, height: 12)
                .position(location)
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: location)
    }
}
