# Quick Reference: Device Filtering Feature

## What Changed?

### Files Added:
1. **DeviceIdentifierService.swift** - Manages persistent device ID in Keychain

### Files Modified:
1. **CloudflareWorkerService.swift** - Appends device ID to filenames
2. **CloudflareVideoHistoryService.swift** - Filters videos by device ID
3. **ContentView.swift** - Added secret tap unlock in InstructionsView
4. **UploadHistoryView.swift** - Added device filter indicator banner

## How It Works

### Upload Process:
```
Original filename: myVideo.mp4
       ↓
Device ID: 12345678
       ↓
Final filename: myVideo_12345678.mp4
```

### History Filtering:
```
Mode: Device Only (default)
  → Shows videos with "_12345678" in filename
  → Banner: Blue "This Device Only"

Mode: All Devices (unlocked)
  → Shows all videos
  → Banner: Orange "Viewing All Devices"
```

## User Instructions

### For You (Developer):
- Device ID is automatically generated on first launch
- Stored in Keychain, persists across app deletions
- No user action required for basic functionality

### For End Users:
**Default Behavior:**
- Upload history shows only their device's uploads
- No configuration needed

**To View All Devices:**
1. Open Instructions (ℹ️ button)
2. Tap the app logo 10 times quickly
3. Alert confirms unlock
4. Return to history to see all uploads

**To Return to Device-Only Mode:**
- Tap logo 10 times again

## Testing Commands

```swift
// Get current device ID
print(DeviceIdentifierService.shared.deviceIdentifier)
print(DeviceIdentifierService.shared.shortDeviceIdentifier)

// Check filter mode
print(CloudflareVideoHistoryService.shared.showAllDevices)

// Manually toggle (for testing)
Task {
    await CloudflareVideoHistoryService.shared.toggleShowAllDevices()
}

// Reset device ID (debugging only)
DeviceIdentifierService.shared.resetDeviceIdentifier()
```

## Visual Indicators

### InstructionsView Logo:
- **No taps:** Normal logo
- **1-9 taps:** Progress ring appears around logo (animated)
- **10 taps:** Ring completes, alert shows, haptic success

### UploadHistoryView Banner:
- **Device Only:** 
  - 📱 iPhone icon
  - Blue background
  - Shows device ID
  
- **All Devices:**
  - 🌐 Globe icon + ✅ Checkmark
  - Orange/purple gradient
  - More prominent

## API Reference

### DeviceIdentifierService
```swift
// Get full UUID
DeviceIdentifierService.shared.deviceIdentifier
// Returns: "12345678-1234-5678-1234-567812345678"

// Get short version (used in filenames)
DeviceIdentifierService.shared.shortDeviceIdentifier
// Returns: "12345678"

// Reset (debugging only)
DeviceIdentifierService.shared.resetDeviceIdentifier()
```

### CloudflareVideoHistoryService
```swift
// Check current mode
historyService.showAllDevices // Bool

// Toggle mode
await historyService.toggleShowAllDevices()

// Get device ID for display
historyService.currentDeviceID // String

// Refresh with current filter
await historyService.fetchVideos()
```

## Troubleshooting

**Issue:** Device ID changes after app reinstall
- **Cause:** Keychain item was manually deleted or device was reset
- **Solution:** This is expected behavior only after full device reset

**Issue:** History shows no videos
- **Possible causes:**
  1. No uploads from this device yet
  2. Filenames don't include device ID (old uploads)
  3. Network error
- **Solution:** Unlock all devices mode to check

**Issue:** Can't unlock all devices mode
- **Cause:** Not tapping fast enough (3-second timeout)
- **Solution:** Tap 10 times within 3 seconds

**Issue:** Banner doesn't update after unlocking
- **Cause:** View needs refresh
- **Solution:** History view should auto-refresh, or pull to refresh

## Privacy Considerations

✅ **What the device ID is:**
- Random UUID generated locally
- Stored only in device Keychain
- Not linked to Apple ID or device serial

❌ **What it's NOT:**
- Not device IMEI or serial number
- Not linked to user identity
- Not shared with third parties
- Not used for tracking

## Deployment Checklist

Before releasing:
- [ ] Test first launch (device ID generation)
- [ ] Test upload with device ID in filename
- [ ] Test history filtering (both modes)
- [ ] Test secret unlock gesture
- [ ] Test persistence after app restart
- [ ] Test on multiple devices
- [ ] Verify Keychain access in capabilities
- [ ] Update privacy policy if needed
- [ ] Test with existing videos (no device ID)

## Backend Considerations

Your Cloudflare Worker doesn't need changes, but be aware:
- Filenames now include `_<deviceID>` suffix
- Older uploads won't have device IDs
- You could add device ID as metadata instead of filename (future enhancement)

## Example Scenarios

### Scenario 1: Single User, One Device
- User uploads videos → all have same device ID
- History shows all their uploads (filtered mode works same as all mode)
- Clean experience

### Scenario 2: Single User, Multiple Devices
- User has app on iPhone and iPad
- Each device has different ID
- By default, sees only current device's uploads
- Can unlock to see everything

### Scenario 3: Shared Account (if applicable)
- Multiple people upload to same cloud
- Each device filters its own uploads
- Unlock required to see others' uploads
- Privacy-friendly default

## Future Ideas

Consider implementing:
1. **Device Naming:** Let users name their devices ("My iPhone", "Work iPad")
2. **Settings Toggle:** Make unlock a permanent setting
3. **Device Management:** List all devices with upload counts
4. **Smart Grouping:** Group uploads by device in list
5. **Transfer Mode:** Generate codes to "link" devices
