import SwiftUI

struct CaptureButtonPanelView: View {
    @ObservedObject var model: ARViewModel
    var width: CGFloat
    
    var body: some View {
        HStack(spacing: 40) {
            Spacer()
            
            // Take Picture Button
            Button(action: {
                model.capturePhoto()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 68, height: 68)
                }
            }
            .disabled(!model.isSessionActive)
            .opacity(model.isSessionActive ? 1.0 : 0.5)
            
            // Start/Finish Button
            Button(action: {
                if model.isSessionActive {
                    model.finishSession()
                } else {
                    model.startSession()
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }) {
                Text(model.isSessionActive ? "Finish" : "Start")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding()
                    .frame(minWidth: 100)
                    .background(model.isSessionActive ? Color.red : Color.blue)
                    .clipShape(Capsule())
            }
            
            Spacer()
        }
        .padding(.bottom, 30)
        .frame(width: width)
        .animation(.spring(), value: model.isSessionActive)
    }
}
