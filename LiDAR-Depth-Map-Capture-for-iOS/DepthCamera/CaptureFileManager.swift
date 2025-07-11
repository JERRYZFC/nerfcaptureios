//
//  CaptureFileManager.swift
//  DepthCamera
//
//  Created by Assistant on 2025/01/07.
//

import Foundation
import UIKit
import SwiftUI

// MARK: - Data Models
struct CaptureItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    let depthURL: URL
    let imageURL: URL
    let visualDepthURL: URL? // URL for the high-contrast visual depth map
    var thumbnail: UIImage?
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var fileSize: String {
        let depthSize = (try? FileManager.default.attributesOfItem(atPath: depthURL.path)[.size] as? Int) ?? 0
        let imageSize = (try? FileManager.default.attributesOfItem(atPath: imageURL.path)[.size] as? Int) ?? 0
        let visualDepthSize = (try? visualDepthURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int }) ?? 0
        let totalSize = depthSize + imageSize + visualDepthSize
        return ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
}

// MARK: - File Manager
class CaptureFileManager: ObservableObject {
    @Published var captures: [CaptureItem] = []
    @Published var isLoading = false
    
    private let documentsDirectory: URL
    
    init() {
        self.documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        loadCaptures()
    }
    
    func loadCaptures() {
        isLoading = true
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            var items: [CaptureItem] = []
            
            do {
                let dateDirectories = try FileManager.default.contentsOfDirectory(
                    at: self.documentsDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                
                for dateDir in dateDirectories {
                    let isDirectory = (try? dateDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if !isDirectory { continue }
                    
                    let files = try FileManager.default.contentsOfDirectory(
                        at: dateDir,
                        includingPropertiesForKeys: [.creationDateKey],
                        options: [.skipsHiddenFiles]
                    )
                    
                    var fileGroups: [String: [URL]] = [:]
                    for file in files {
                        let filename = file.lastPathComponent
                        if let timestampEnd = filename.firstIndex(of: "_") {
                            let timestamp = String(filename[..<timestampEnd])
                            fileGroups[timestamp, default: []].append(file)
                        }
                    }
                    
                    for (timestamp, urls) in fileGroups {
                        guard let depthURL = urls.first(where: { $0.pathExtension == "tiff" }),
                              let imageURL = urls.first(where: { $0.pathExtension == "jpg" }) else {
                            continue
                        }
                        
                        // Find the visual depth map, which is optional for backward compatibility
                        let visualDepthURL = urls.first(where: { $0.lastPathComponent.contains("_depth_visual.png") })
                        
                        let timestampDouble = Double(timestamp) ?? 0
                        let date = Date(timeIntervalSince1970: timestampDouble)
                        
                        let thumbnail = self.generateThumbnail(from: imageURL)
                        
                        items.append(CaptureItem(
                            timestamp: date,
                            depthURL: depthURL,
                            imageURL: imageURL,
                            visualDepthURL: visualDepthURL,
                            thumbnail: thumbnail
                        ))
                    }
                }
                
                items.sort { $0.timestamp > $1.timestamp }
                
                DispatchQueue.main.async {
                    self.captures = items
                    self.isLoading = false
                }
            } catch {
                print("Error loading captures: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
    
    func deleteCapture(_ capture: CaptureItem) {
        do {
            try FileManager.default.removeItem(at: capture.depthURL)
            try FileManager.default.removeItem(at: capture.imageURL)
            if let visualURL = capture.visualDepthURL {
                try FileManager.default.removeItem(at: visualURL)
            }
            
            captures.removeAll { $0.id == capture.id }
            
            let directory = capture.depthURL.deletingLastPathComponent()
            if let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil), contents.isEmpty {
                try FileManager.default.removeItem(at: directory)
            }
        } catch {
            print("Error deleting capture: \(error)")
        }
    }
    
    func shareCapture(_ capture: CaptureItem) -> [Any] {
        var itemsToShare: [Any] = [capture.imageURL, capture.depthURL]
        if let visualURL = capture.visualDepthURL {
            itemsToShare.append(visualURL)
        }
        return itemsToShare
    }
    
    private func generateThumbnail(from imageURL: URL) -> UIImage? {
        guard let image = UIImage(contentsOfFile: imageURL.path) else { return nil }
        
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return thumbnail
    }
}
