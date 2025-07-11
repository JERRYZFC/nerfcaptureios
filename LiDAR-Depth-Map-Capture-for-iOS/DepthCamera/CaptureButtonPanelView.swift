import SwiftUI

struct CaptureButtonPanelView: View {
    @ObservedObject var model: ARViewModel
    var width: CGFloat
    
    var body: some View {
        HStack {
            Spacer()
            CaptureButton(model: model)
            Spacer()
        }
        .padding(.bottom, 30)
    }
}
