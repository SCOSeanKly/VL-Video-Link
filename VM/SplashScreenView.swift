//
//  SplashScreenView.swift
//  VM
//
//  Created by Sean Kelly on 20/11/2025.
//

import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    @State private var progressOpacity: Double = 0.0
    
    var body: some View {
        if isActive {
            ContentView()
                .permissionSheet([.photoLibrary, .camera, .microphone])
        } else {
            
            VStack(spacing: 30) {
                Spacer()
                
                // Logo with animation
                Image("link")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 36))
                    .shadow(color: .blue.opacity(0.2), radius: 5, x: 0, y: 4)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                
                // App name
                VStack(spacing: 8) {
                    Text("VL")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.black)
                    
                    Text("Professional Video Linker")
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.9))
                }
                .opacity(textOpacity)
                
                Spacer()
                
                // Loading indicator
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.black)
                        .scaleEffect(1.2)
                    
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.black.opacity(0.8))
                }
                .opacity(progressOpacity)
                .padding(.bottom, 60)
            }
            .onAppear {
                // Animate logo appearance
                withAnimation(.easeOut(duration: 0.8)) {
                    logoScale = 1.0
                    logoOpacity = 1.0
                }
                
                // Animate text appearance
                withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                    textOpacity = 1.0
                }
                
                // Animate progress indicator
                withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                    progressOpacity = 1.0
                }
                
                // Transition to main view
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        isActive = true
                    }
                }
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
