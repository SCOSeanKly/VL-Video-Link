# Device-Specific History Filtering Implementation

## Overview
This implementation adds device-specific filtering to the upload history, allowing users to see only videos uploaded from their current device by default, with the ability to unlock viewing all devices through a secret gesture.

## Key Components

### 1. DeviceIdentifierService.swift (NEW)
A service that manages a persistent device identifier using the iOS Keychain.

**Features:**
- Generates a unique UUID on first launch
- Stores identifier in Keychain (persists across app deletions)
- Provides both full and short (8-character) identifiers
- Includes debug method to reset identifier

**Why Keychain?**
- Persists even after app deletion and reinstall
- More reliable than `identifierForVendor` (which resets when all vendor apps are deleted)
- Secure storage managed by iOS

### 2. Updated CloudflareWorkerService.swift
Modified to automatically append device identifier to all uploaded filenames.

**Changes:**
- Imports `DeviceIdentifierService`
- Appends `_<deviceID>` to all uploaded filenames before the extension
- Examples:
  - `myVideo.mp4` → `myVideo_ABC12345.mp4`
  - `UUID.mp4` → `<UUID>_ABC12345.mp4`

### 3. Updated CloudflareVideoHistoryService.swift
Enhanced to filter videos based on device identifier.

**New Features:**
- `showAllDevices` property to toggle between filtered/unfiltered views
- Automatic filtering of videos by device ID in filename
- `toggleShowAllDevices()` method to switch modes
- `currentDeviceID` property for display purposes

**Filtering Logic:**
```swift
if showAllDevices {
    // Show all videos
} else {
    // Filter videos where filename contains "_<deviceID>"
}
```

### 4. Updated ContentView.swift - InstructionsView
Added secret tap gesture to unlock all-device viewing.

**Secret Unlock Feature:**
- Tap the app logo 10 times in the Instructions view
- Progress haptic feedback at milestone (5 taps)
- Success haptic and alert when unlocked
- Auto-reset after 3 seconds of inactivity
- Toggle behavior: tapping 10 times again will switch back to device-only mode

**Implementation:**
- `secretTapCount` state variable
- `handleSecretTap()` method with haptic feedback
- Alert showing unlock status
- Task-based timeout for counter reset

### 5. Updated UploadHistoryView.swift
Added visual indicator banner showing current filter mode.

**Banner Features:**
- **Device-Only Mode:**
  - Blue background
  - Shows "This Device Only"
  - Displays current device ID (8 characters)
  - iPhone icon

- **All Devices Mode:**
  - Orange/purple gradient background
  - Shows "Viewing All Devices"
  - Globe icon with green checkmark
  - More prominent to indicate special mode

## User Experience Flow

### Default Behavior:
1. User uploads video → filename automatically includes device ID
2. User opens History → sees only their device's uploads
3. Banner shows "This Device Only" with device ID

### Unlocking All Devices:
1. User opens Instructions view
2. Taps logo 10 times (with haptic feedback)
3. Alert confirms "All History Unlocked!"
4. History view now shows all uploads with orange banner
5. User can toggle back by tapping logo 10 times again

## Technical Details

### Device Identifier Format:
- Full: `12345678-1234-5678-1234-567812345678` (UUID)
- Short: `12345678` (first 8 characters)
- Used in filenames: `_12345678`

### Filename Examples:
- User upload: `vacation_12345678.mp4`
- Auto-generated: `A3B2C4D1-...-EFGH_12345678.mp4`

### Keychain Configuration:
- Service: `com.yourcompany.vm.deviceid`
- Account: `device-identifier`
- Accessibility: `kSecAttrAccessibleAfterFirstUnlock`

## Benefits

1. **Privacy**: Users only see their own uploads by default
2. **Persistence**: Device ID survives app deletion/reinstall
3. **Flexibility**: Power users can unlock all devices view
4. **Discovery**: Secret gesture is fun and doesn't clutter UI
5. **Reversible**: Can toggle between modes freely

## Testing Checklist

- [ ] First launch generates and stores device ID
- [ ] Device ID persists after app restart
- [ ] Device ID persists after app deletion/reinstall
- [ ] Uploaded filenames include device ID
- [ ] History shows only this device's uploads by default
- [ ] Banner correctly shows current mode
- [ ] Secret tap counter works (10 taps)
- [ ] Haptic feedback at milestones
- [ ] Alert displays on unlock
- [ ] All devices mode shows all uploads
- [ ] Can toggle back to device-only mode
- [ ] Search works in both modes

## Future Enhancements

Consider adding:
- Settings toggle instead of secret gesture (more discoverable)
- Device nickname/name instead of just ID
- Multi-device management (see which device uploaded what)
- Cloud sync of device preferences
- Export device-specific upload list

## Notes

- Device ID cannot be traced back to actual hardware serial numbers (privacy-compliant)
- Users on multiple devices will have different IDs per device
- If user wants to see uploads from another device, they must unlock all devices mode
- The 10-tap secret is intentionally undocumented (Easter egg style)
