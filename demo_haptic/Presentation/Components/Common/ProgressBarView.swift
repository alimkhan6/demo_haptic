import SwiftUI

struct ProgressBarView: View {
    let progress: AnalysisProgress
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress details
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.step.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text("\(Int(progress.progress * 100))% of current step")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(progress.overallProgress * 100))%")
                        .font(.caption)
                        .fontWeight(.bold)
                    
                    if let timeRemaining = progress.estimatedTimeRemaining {
                        Text("~\(timeRemaining.formattedEstimate)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                    
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * CGFloat(progress.overallProgress),
                            height: 6
                        )
                        .animation(.linear(duration: 0.3), value: progress.overallProgress)
                }
                .cornerRadius(3)
            }
            .frame(height: 6)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }
}
