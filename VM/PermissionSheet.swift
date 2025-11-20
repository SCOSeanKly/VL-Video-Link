//
//  PermissionSheet.swift
//  PermissionTutorial
//
//  Created by Balaji Venkatesh on 21/07/25.
//

import SwiftUI
import PhotosUI
import AVKit

extension Font {
    /// Section/page headings. Rounded for a friendly brand tone.
    static var brandTitle: Font { .system(.title2, design: .rounded) }
    /// Row titles and strong labels.
    static var brandHeadline: Font { .system(.headline, design: .rounded) }
    /// Default body text used for most secondary copy.
    static var brandBody: Font { .system(.subheadline, design: .rounded) }
    /// Small labels/badges. Slightly larger than caption for legibility.
    static var brandLabel: Font { .callout }
    /// Tiny auxiliary labels.
    static var brandCaption: Font { .caption2 }

}



/// Permissions
enum Permission: String, CaseIterable {
 
    case photoLibrary = "Photo Library Access"
    case camera = "Camera Access"
    case microphone = "Microphone Access"
        
    var symbol: String {
        switch self {
        case .photoLibrary: return "photo.stack.fill"
        case .camera: return "camera.fill"
        case .microphone: return "mic.fill"
        }
    }
    
    var orderedIndex: Int {
        switch self {
        case .photoLibrary: return 0
        case .camera: return 1
        case .microphone: return 2
        }
    }
    
    var isGranted: Bool? {
        switch self {
        case .photoLibrary:
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            /// LIMITED IS OPTIONAL!
            return status == .notDetermined ? nil : status == .authorized || status == .limited
        case .camera:
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            return status == .notDetermined ? nil : status == .authorized
        case .microphone:
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            return status == .notDetermined ? nil : status == .authorized
        }
    }
}

extension View {
    @ViewBuilder
    func permissionSheet(_ permissions: [Permission]) -> some View {
        self
            .modifier(PermissionSheetViewModifier(permissions: permissions))
    }
}

fileprivate struct PermissionSheetViewModifier: ViewModifier {
    init(permissions: [Permission]) {
        let initialStates = permissions.sorted(by: {
            $0.orderedIndex < $1.orderedIndex
        }).compactMap {
            PermissionState(id: $0)
        }
        
        self._states = .init(initialValue: initialStates)
    }
    
    /// View Properties
    @State private var showSheet: Bool = false
    @State private var states: [PermissionState]
    @State private var currentIndex: Int = 0
    @Environment(\.openURL) var openURL
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showSheet) {
                VStack(spacing: 20) {
                    Text("Required Permissions")
                        .font(.brandTitle)
                        .fontWeight(.bold)
                    
                    Text("VL needs access to your photo library, camera, and microphone so you can import, record, and share video links.")
                        .font(.brandBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Image(systemName: isAllGranted ? "person.badge.shield.checkmark" : "person.badge.shield.exclamationmark")
                        .font(.system(size: 60))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 100, height: 100)
                        .background {
                            RoundedRectangle(cornerRadius: 30)
                                .fill(Color.blue.gradient)
                        }
                    
                    /// Permission Rows
                    VStack(alignment: .leading, spacing: 20) {
                        Spacer()
                        ForEach(states) { state in
                            PermissionRow(state)
                                /// Manual Requesting
                                .contentShape(.rect)
                                .onTapGesture {
                                    requestPermission(state.id.orderedIndex)
                                }
                        }
                        Spacer()
                    }
                    .padding(.top, 10)
                    
                    Spacer(minLength: 0)
                    
                        if isThereAnyRejection {
                            Button("Go to Settings") {
                                if let appSettingsURL = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(appSettingsURL)
                                }
                            }
                        }
                    
                }
               
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
                .presentationDetents([.height(520)])
                .interactiveDismissDisabled()
              // .background(Color.brandSurface)
            }
            .onChange(of: currentIndex) { oldValue, newValue in
                guard states[newValue].isGranted == nil else { return }
                requestPermission(newValue)
            }
            .onChange(of: isAllGranted) { oldValue, newValue in
                if newValue {
                    showSheet = false
                }
            }
            .onAppear {
                showSheet = !isAllGranted
                if let firstRequestPermission = states.firstIndex(where: { $0.isGranted == nil }) {
                    /// Setting up current index
                    currentIndex = firstRequestPermission
                    requestPermission(firstRequestPermission)
                }
            }
    }
    
    @ViewBuilder
    private func PermissionRow(_ state: PermissionState) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(.gray, lineWidth: 1)
                
                Group {
                    if let isGranted = state.isGranted {
                        Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(isGranted ? .green : .red)
                    } else {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(.gray)
                    }
                }
                .font(.brandHeadline)
                .transition(.symbolEffect)
            }
            .frame(width: 22, height: 22)
            
            Text(state.id.rawValue)
        }
        .lineLimit(1)
    }
    
    private func requestPermission(_ index: Int) {
        Task { @MainActor in
            let permission = states[index].id
            
            switch permission {
            case .photoLibrary:
                let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                /// LIMITED IS OPTIONAL!
                states[index].isGranted = status == .authorized || status == .limited
            case .camera:
                let status = await AVCaptureDevice.requestAccess(for: .video)
                states[index].isGranted = status
            case .microphone:
                let status = await AVCaptureDevice.requestAccess(for: .audio)
                states[index].isGranted = status
            }
            
            /// Updated Index
            currentIndex = min(currentIndex + 1, states.count - 1)
        }
    }
    
    private var isAllGranted: Bool {
        states.filter({ $0.isGranted == true }).count == states.count
    }
    
    private var isThereAnyRejection: Bool {
        states.contains(where: { $0.isGranted == false })
    }
    
    private struct PermissionState: Identifiable {
        var id: Permission
        /// For Dynamic Updates!
        var isGranted: Bool?
        
        /// Setting up the initial value
        init(id: Permission) {
            self.id = id
            self.isGranted = id.isGranted
        }
    }
}


