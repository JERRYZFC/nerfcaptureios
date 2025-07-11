//
//  CaptureButton.swift
//  DepthCamera
//
//  Created by iori on 2024/11/27.
//

import SwiftUICore
import SwiftUI

struct CaptureButton: View {
    static let outerDiameter: CGFloat = 80
    static let strokeWidth: CGFloat = 4
    static let innerPadding: CGFloat = 10
    static let innerDiameter: CGFloat = CaptureButton.outerDiameter - CaptureButton.strokeWidth - CaptureButton.innerPadding
    static let rootTwoOverTwo: CGFloat = CGFloat(2.0.squareRoot() / 2.0)
    static let squareDiameter: CGFloat = CaptureButton.innerDiameter * CaptureButton.rootTwoOverTwo - CaptureButton.innerPadding
    
    @ObservedObject var model: ARViewModel
    
    init(model: ARViewModel) {
        self.model = model
    }
    
    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                if model.isRecording {
                    model.stopRecording()
                } else {
                    model.startRecording()
                }
            }
        }) {
            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(Color.white, lineWidth: CaptureButton.strokeWidth)
                    .frame(width: CaptureButton.outerDiameter, height: CaptureButton.outerDiameter)
                
                // Inner shape that animates based on recording state
                if model.isRecording {
                    RoundedRectangle(cornerRadius: CaptureButton.squareDiameter / 4)
                        .fill(Color.red)
                        .frame(width: CaptureButton.squareDiameter, height: CaptureButton.squareDiameter)
                        .transition(.scale)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: CaptureButton.innerDiameter, height: CaptureButton.innerDiameter)
                        .transition(.scale)
                }
            }
        }
    }
}
