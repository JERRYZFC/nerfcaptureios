import SwiftUI
import ARKit
import RealityKit

struct ContentView : View {
    @StateObject var arViewModel = ARViewModel()
    @State private var showDepthMap: Bool = true
    @State private var showConfidenceMap: Bool = true
    @State private var depthMapScale: CGFloat = 1.0
    @State private var confidenceMapScale: CGFloat = 1.0
    let previewCornerRadius: CGFloat = 20.0
    
    var body: some View {
        
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width * 4 / 3 // 4:3 aspect ratio
            ZStack {
                // Make the entire background black.
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
                    // Top control panel
                    HStack(spacing: 20) {
                        // Depth map controls
                        VStack(alignment: .center, spacing: 12) {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showDepthMap.toggle()
                                    depthMapScale = showDepthMap ? 1.0 : 0.8
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: showDepthMap ? "cube.fill" : "cube")
                                    Text("Depth")
                                }
                                .modifier(ControlButtonModifier(isActive: showDepthMap, activeColor: .blue))
                            }
                            .scaleEffect(depthMapScale)
                            
                            if showDepthMap, let depthImage = arViewModel.processedDepthImage {
                                Image(uiImage: depthImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: width * 0.25, height: width * 0.25)
                                    .modifier(PreviewImageModifier(activeColor: .blue))
                            }
                        }
                        
                        // Confidence map controls
                        VStack(alignment: .center, spacing: 12) {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showConfidenceMap.toggle()
                                    confidenceMapScale = showConfidenceMap ? 1.0 : 0.8
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: showConfidenceMap ? "shield.fill" : "shield")
                                    Text("Confidence")
                                }
                                .modifier(ControlButtonModifier(isActive: showConfidenceMap, activeColor: .green))
                            }
                            .scaleEffect(confidenceMapScale)
                            
                            if showConfidenceMap, let confidenceImage = arViewModel.processedConfidenceImage {
                                Image(uiImage: confidenceImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: width * 0.25, height: width * 0.25)
                                    .modifier(PreviewImageModifier(activeColor: .green))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 50)
                    .background(
                        LinearGradient(colors: [Color.black.opacity(0.9), Color.black.opacity(0.7), Color.clear],
                                     startPoint: .top,
                                     endPoint: .bottom)
                            .ignoresSafeArea(edges: .top)
                            .allowsHitTesting(false)
                    )
                    
                    Spacer()
                    
                    // Main ARView
                    ARViewContainer(arViewModel: arViewModel)
                        .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: previewCornerRadius)
                                .stroke(LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 10)
                        .frame(width: width * 0.9, height: height * 0.9)
                        .scaleEffect(0.95)
                    
                    Spacer()
                    
                    CaptureButtonPanelView(model: arViewModel, width: geometry.size.width)
                        .padding(.bottom, 30)
                }
                
                // Recording Indicator
                if arViewModel.isRecording {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                                .scaleEffect(1.2)
                                .animation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: arViewModel.isRecording)
                            
                            Text("REC")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.red)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                        .padding(.trailing)
                        .padding(.top, geometry.safeAreaInsets.top)
                        
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - View Modifiers for DRY principle

struct ControlButtonModifier: ViewModifier {
    let isActive: Bool
    let activeColor: Color
    
    func body(content: Content) -> some View {
        content
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ?
                        LinearGradient(colors: [activeColor, activeColor.opacity(0.8)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing) :
                        LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: isActive ? activeColor.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
    }
}

struct PreviewImageModifier: ViewModifier {
    let activeColor: Color
    
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(LinearGradient(colors: [activeColor.opacity(0.6), activeColor.opacity(0.2)],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing), lineWidth: 2)
            )
            .shadow(color: activeColor.opacity(0.3), radius: 10, x: 0, y: 5)
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .scale.combined(with: .opacity)
            ))
    }
}
