import SwiftUI

struct ErrorMessageView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
            .padding()
    }
}
