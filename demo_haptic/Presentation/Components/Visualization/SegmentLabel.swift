//
//  SegmentLabel.swift
//  haptico
//
//  Segment label component showing current song section
//

import SwiftUI

struct SegmentLabel: View {
    let segment: Segment?
    
    var body: some View {
        if let segment = segment {
            Text(segment.type.rawValue.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(segmentColor(segment.type))
                .foregroundColor(.white)
                .cornerRadius(12)
        }
    }
    
    private func segmentColor(_ type: SegmentType) -> Color {
        switch type {
        case .intro: return .gray
        case .verse: return .blue
        case .chorus: return .orange
        case .bridge: return .purple
        case .outro: return .gray
        }
    }
}
