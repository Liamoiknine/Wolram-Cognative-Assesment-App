# Setup Instructions

## Option 1: Create New Xcode Project (Recommended)

1. **Open Xcode** and create a new project:
   - File → New → Project
   - Choose "iOS" → "App"
   - Product Name: `CognitiveAssessmentApp`
   - Interface: SwiftUI
   - Language: Swift
   - Save it in a **different location** (we'll copy files over)

2. **Copy the source files**:
   - In Finder, copy all folders from `Sources/` in this directory
   - In Xcode, right-click your project → "Add Files to [ProjectName]"
   - Select all the folders (Models, Data, Storage, Audio, Transcription, Assessment, UI)
   - Make sure "Copy items if needed" is checked
   - Click "Add"

3. **Update the App file**:
   - Xcode will create a default `App.swift` or `ContentView.swift`
   - Delete the default files
   - The `CognitiveAssessmentApp.swift` from `UI/App/` should be your main app entry point

4. **Add required frameworks**:
   - Select your project in the navigator
   - Go to "Signing & Capabilities"
   - Add capabilities if needed:
     - Microphone (for audio recording)
     - Speech Recognition (for transcription)

5. **Build and Run**:
   - Select an iOS Simulator or device
   - Press ⌘R or click the Play button

## Option 2: Use Swift Package Manager (For Library/Testing)

If you want to use this as a Swift Package:

1. Create a `Package.swift` file in the root directory
2. The `Sources/` structure is already SwiftPM-compatible
3. However, for an iOS app, Option 1 is still recommended

## Quick Test

Once set up in Xcode, you should be able to:
- See the home screen with "Start Assessment" and "Session History" buttons
- Navigate between screens (though tasks won't work yet since no tasks are implemented)

## Troubleshooting

- **Import errors**: Make sure all files are added to the Xcode target
- **Framework errors**: Ensure AVFoundation and Speech frameworks are linked (they should be automatic)
- **App entry point**: Make sure `CognitiveAssessmentApp.swift` is set as the main app file

