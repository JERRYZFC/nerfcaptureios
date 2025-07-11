//
//  CaptureButton.swift
//  DepthCamera
//
//  Created by iori on 2024/11/27.
//

import SwiftUI

struct CaptureButton: View {
    @ObservedObject var model: ARViewModel
    
    var body: some View {
        Button(action: {
            // Provide haptic feedback on tap
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            // Toggle recording state
            if model.isRecording {
                model.stopRecording()
            } else {
                model.startRecording()
            }
        }) {
            ZStack {
                // Outer ring with gradient and shadow
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: model.isRecording ? Color.red.opacity(0.5) : Color.white.opacity(0.3), radius: 8, x: 0, y: 4)
                
                // Inner shape that animates between circle and square
                if model.isRecording {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red)
                        .frame(width: 35, height: 35)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color.gray.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 68, height: 68)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Pulsing effect when recording
                if model.isRecording {
                    Circle()
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: 80, height: 80)
                        .scaleEffect(1.2)
                        .opacity(0)
                        .animation(
                            .easeInOut(duration: 1.5).repeatForever(autoreverses: false),
                            value: model.isRecording
                        )
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: model.isRecording)
    }
}
