//
//  LayerBar.swift
//  haptico
//
//  Layer bar component for haptic visualization
//

import SwiftUI

struct LayerBar: View {
    let title: String
    let value: Float
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.7), color],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: geometry.size.height * CGFloat(value))
                        .animation(.linear(duration: 0.05), value: value)
                }
            }
        }
    }
}
