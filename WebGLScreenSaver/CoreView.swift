import SwiftUI

struct CoreView: View {
    @State private var time = 0.0

    var body: some View {
        DisplayLinkReader { displayLink in
            GeometryReader { geometry in
                let radius = min(geometry.size.height, geometry.size.width)
                return Color.white
                    .overlay {
                        Circle()
                            .fill(.gray)
                            .frame(width: radius, height: radius)
                            .scaleEffect(1.0 * sin(time))
                            .blur(radius: 0.1 * radius)
                    }
                    .onAppear {
                        displayLink.start {
                            // Update position of the image
                            time += 0.03
                        }
                    }
                    .onDisappear {
                        displayLink.stop()
                    }
            }
        }
    }
}

#Preview {
    CoreView()
}
