//
//  CaptureListView.swift
//  DepthCamera
//
//  Created by Assistant on 2025/01/07.
//

import SwiftUI

struct CaptureListView: View {
    @StateObject private var fileManager = CaptureFileManager()
    @State private var itemToShare: ShareableFile?
    @State private var showingDeleteAlert = false
    @State private var captureToDelete: CaptureItem?
    @State private var searchText = ""
    
    var filteredCaptures: [CaptureItem] {
        if searchText.isEmpty {
            return fileManager.captures
        } else {
            return fileManager.captures.filter { capture in
                capture.name.localizedCaseInsensitiveContains(searchText) ||
                capture.formattedDate.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if fileManager.isLoading {
                    ProgressView("Loading captures...")
                        .foregroundColor(.white)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if fileManager.captures.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No captures yet")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text("Start a recording to create your first dataset.")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.8))
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
                        ], spacing: 16) {
                            ForEach(filteredCaptures) { capture in
                                CaptureItemView(
                                    capture: capture,
                                    onDelete: {
                                        captureToDelete = capture
                                        showingDeleteAlert = true
                                    },
                                    onShare: {
                                        fileManager.shareCapture(capture) { url in
                                            if let url = url {
                                                itemToShare = ShareableFile(url: url)
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Captures")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search captures")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: fileManager.loadCaptures) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $itemToShare) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert("Delete Capture", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let capture = captureToDelete {
                    withAnimation {
                        fileManager.deleteCapture(capture)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this capture? This action cannot be undone.")
        }
    }
}

struct CaptureItemView: View {
    let capture: CaptureItem
    let onDelete: () -> Void
    let onShare: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail
            ZStack {
                if let thumbnail = capture.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 150)
                        .overlay(
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        )
                }
                
                // Top gradient for better icon visibility
                LinearGradient(
                    colors: [Color.black.opacity(0.6), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                
                // Action buttons
                HStack {
                    Spacer()
                    Menu {
                        Button(action: onShare) {
                            Label("Share as .zip", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.3).blur(radius: 10))
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            
            // Info section
            VStack(alignment: .leading, spacing: 4) {
                Text(capture.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack {
                    Image(systemName: "photo.stack")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text("\(capture.frameCount) frames")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(capture.fileSize)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.8))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 8, x: 0, y: 4)
    }
}

// Wrapper for URL to make it Identifiable for the .sheet modifier
struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
