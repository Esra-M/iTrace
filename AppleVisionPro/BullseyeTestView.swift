import SwiftUI

struct BullseyeTestView: View {
    @State private var lastTapLocation: CGPoint = .zero
    @State private var showResult = false
    @State private var precision: Double = 0.0
    
    @EnvironmentObject var appState: AppState
    
    let bullseyeRadius: CGFloat = 150
    
    var body: some View {
        ZStack {
            VStack(spacing: 30) {
                Text("Tap the center of the circle")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                ZStack {
                    ForEach(0..<5, id: \.self) { i in
                        let opacity: Double = 0.2 + (Double(i) * 0.2)
                        let size: CGFloat = bullseyeRadius * (2.0 - (CGFloat(i) * 0.4))
                        
                        Circle()
                            .fill(Color.white.opacity(opacity))
                            .frame(width: size, height: size)
                    }
                    
                    ZStack {
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: 20, height: 2)
                        
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: 2, height: 20)
                    }
                    
                    if showResult {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 20, height: 20)
                            .position(lastTapLocation)
                    }
                }
                .frame(width: bullseyeRadius * 2, height: bullseyeRadius * 2)
                .contentShape(Circle())
                .onTapGesture { location in
                    lastTapLocation = location
                    let center = CGPoint(x: bullseyeRadius, y: bullseyeRadius)
                    let distance = sqrt(pow(location.x - center.x, 2) + pow(location.y - center.y, 2))
                    precision = max(0.0, (1.0 - Double(distance / bullseyeRadius)) * 100.0)
                    showResult = true
                }
                
                VStack {
                    if showResult {
                        Text("Precision: \(precision, specifier: "%.1f")%")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }
                .frame(height: 40)
            }
            .padding(.top, 100)
            
            Button(action: {
                appState.currentPage = .test
            }) {
                Image(systemName: "chevron.backward")
                    .padding(20)
            }
            .offset(x: -580, y: -300)
            .frame(width: 60, height: 60)
        }
    }
}
