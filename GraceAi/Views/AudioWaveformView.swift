import SwiftUI

struct AudioWaveformView: View {
    let amplitudes: [CGFloat]
    var color: Color = .blue
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2
    var minBarHeight: CGFloat = 3
    
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<amplitudes.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: barWidth, height: max(minBarHeight, amplitudes[index] * 50))
                    .animation(.easeInOut(duration: 0.2), value: amplitudes[index])
            }
        }
        .frame(height: 50)
        .onAppear {
            isAnimating = true
        }
    }
}

struct AudioWaveformView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AudioWaveformView(
                amplitudes: [0.2, 0.5, 0.3, 0.8, 0.4, 0.6, 0.3, 0.5, 0.7, 0.4],
                color: .blue
            )
            
            AudioWaveformView(
                amplitudes: [0.1, 0.3, 0.7, 0.5, 0.2, 0.8, 0.6, 0.3, 0.4, 0.2],
                color: .green
            )
            
            AudioWaveformView(
                amplitudes: Array(repeating: 0.05, count: 10),
                color: .gray.opacity(0.5)
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
} 