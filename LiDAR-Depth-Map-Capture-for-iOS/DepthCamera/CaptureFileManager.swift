//
//  CaptureFileManager.swift
//  DepthCamera
//
//  Created by Assistant on 2025/01/07.
//

import Foundation
import UIKit
import SwiftUI
import Zip

// MARK: - Data Models
struct CaptureItem: Identifiable {
    let id = UUID()
    let projectURL: URL
    var thumbnail: UIImage?
    var frameCount: Int
    
    var name: String {
        return projectURL.lastPathComponent
    }
    
    var creationDate: Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: projectURL.path)
        return attributes?[.creationDate] as? Date ?? Date()
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: creationDate)
    }
    
    var fileSize: String {
        guard let enumerator = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: [.totalFileSizeKey, .fileSizeKey]),
              let filePaths = enumerator.allObjects as? [URL] else {
            return "0 KB"
        }
        let totalSize = filePaths.reduce(0) { (result, url) -> Int64 in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            return result + size
        }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
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
                let projectDirectories = try FileManager.default.contentsOfDirectory(
                    at: self.documentsDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
                    options: [.skipsHiddenFiles]
                )
                
                for projectDir in projectDirectories {
                    let isDirectory = (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    let transformsURL = projectDir.appendingPathComponent("transforms.json")
                    
                    // A valid project directory must contain transforms.json
                    if isDirectory && FileManager.default.fileExists(atPath: transformsURL.path) {
                        
                        // Read manifest to get frame count
                        var frameCount = 0
                        if let data = try? Data(contentsOf: transformsURL),
                           let manifest = try? JSONDecoder().decode(Manifest.self, from: data) {
                            frameCount = manifest.frames.count
                        }
                        
                        // Generate thumbnail from the first image
                        let firstImageURL = projectDir.appendingPathComponent("images/0.jpg")
                        let thumbnail = self.generateThumbnail(from: firstImageURL)
                        
                        items.append(CaptureItem(
                            projectURL: projectDir,
                            thumbnail: thumbnail,
                            frameCount: frameCount
                        ))
                    }
                }
                
                // Sort by date (newest first)
                items.sort { $0.creationDate > $1.creationDate }
                
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
            try FileManager.default.removeItem(at: capture.projectURL)
            // Remove from array
            captures.removeAll { $0.id == capture.id }
        } catch {
            print("Error deleting capture: \(error)")
        }
    }
    
    func shareCapture(_ capture: CaptureItem, completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            do {
                let zipFilePath = self.documentsDirectory.appendingPathComponent("\(capture.name).zip")
                // Ensure no old zip file exists
                if FileManager.default.fileExists(atPath: zipFilePath.path) {
                    try FileManager.default.removeItem(at: zipFilePath)
                }
                
                try Zip.zipFiles(paths: [capture.projectURL], zipFilePath: zipFilePath, password: nil, progress: nil)
                DispatchQueue.main.async {
                    completion(zipFilePath)
                }
            } catch {
                print("Error creating zip file: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    private func generateThumbnail(from imageURL: URL) -> UIImage? {
        guard let image = UIImage(contentsOfFile: imageURL.path) else { return nil }
        
        let size = CGSize(width: 150, height: 150)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return thumbnail
    }
}
