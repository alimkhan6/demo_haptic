//
//  BPMDisplayView.swift
//  haptico
//
//  BPM Display component
//

import SwiftUI

struct BPMDisplayView: View {
    let bpm: Float
    let confidence: Float
    
    var body: some View {
        VStack(spacing: 5) {
            Text("\(Int(bpm)) BPM")
                .font(.system(size: 60, weight: .bold))
            
            Text("Confidence: \(Int(confidence * 100))%")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
