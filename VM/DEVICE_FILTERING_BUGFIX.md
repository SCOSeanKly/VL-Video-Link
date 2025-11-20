# Device Filtering Bug Fix

## The Problem

You uploaded a video but it didn't appear in the history view, even though the upload succeeded and you received a link.

## Root Cause

The Cloudflare Worker was **generating its own filename** and ignoring the device ID that the iOS app was trying to include:

### Before (Broken):
```javascript
// Worker code - ignored client filename
const fileName = `${sanitizedReference}-${timestamp}-${randomId}.mov`;
// Result: "MyRef-1234567890-abc12345.mov" ❌ No device ID!
```

```swift
// iOS code - generated filename with device ID
finalFileName = "\(UUID().uuidString)_\(deviceID).mp4"
// Result: "UUID-HERE_ABC12345.mp4" 
// But worker overwrites this! ❌
```

## The Solution

We now send the device ID as a **separate form field** and the worker includes it in the filename:

### After (Fixed):
```swift
// iOS sends device ID as form data
body.append("--\(boundary)\r\n".data(using: .utf8)!)
body.append("Content-Disposition: form-data; name=\"deviceId\"\r\n\r\n".data(using: .utf8)!)
body.append(deviceID.data(using: .utf8)!)
```

```javascript
// Worker receives and uses device ID
const deviceId = formData.get('deviceId');
const fileName = `${sanitizedReference}-${timestamp}-${randomId}_${deviceId}.mov`;
// Result: "MyRef-1234567890-abc12345_ABC12345.mov" ✅
```

## Files Changed

### 1. `cloudflare-worker.js`
- Added `deviceId` extraction from form data
- Modified filename generation to append device ID
- Added logging for debugging

### 2. `CloudflareWorkerService.swift`
- Modified `createMultipartBody()` to send device ID as form field
- Added debug logging to track device ID and filename

### 3. `CloudflareVideoHistoryService.swift`
- Added comprehensive debug logging to help diagnose filtering issues
- Shows which filenames are being checked and why they match/don't match

## Testing the Fix

### Step 1: Check the debug output in Xcode console

When you upload a video, you should see:
```
🔍 DEBUG: Device ID for upload: ABC12345
🔍 DEBUG: Generated filename for upload: UUID-HERE_ABC12345.mp4
🔍 DEBUG: Reference number: MyReference
```

### Step 2: Check Cloudflare Worker logs

In your Cloudflare dashboard, you should see:
```
📁 Generated filename: MyReference-1234567890-abc12345_ABC12345.mov
```

### Step 3: Check history filtering

When viewing history, you should see:
```
🔍 DEBUG: Current device ID: ABC12345
🔍 DEBUG: Fetched 5 total videos from server
🔍 DEBUG: All filenames from server:
   - MyReference-1234567890-abc12345_ABC12345.mov
   - OtherRef-0987654321-xyz98765_XYZ98765.mov
🔍 DEBUG: Checking 'MyReference-1234567890-abc12345_ABC12345.mov' for '_ABC12345': true
🔍 DEBUG: Checking 'OtherRef-0987654321-xyz98765_XYZ98765.mov' for '_ABC12345': false
✅ Filtered to 1 videos for this device (ID: ABC12345)
```

## Deployment Steps

1. **Update Cloudflare Worker:**
   - Go to Cloudflare Workers dashboard
   - Edit your worker
   - Replace with updated `cloudflare-worker.js`
   - Click "Save and Deploy"

2. **Rebuild iOS App:**
   - The Swift code changes will be included automatically
   - No need to update existing users immediately

3. **Test:**
   - Upload a new video
   - Check Xcode console for debug output
   - Verify video appears in history
   - Try the "Show All Devices" toggle (tap logo 10 times)

## Backward Compatibility

**Old videos** (uploaded before this fix) won't have device IDs in their filenames:
- Format: `MyRef-1234567890-abc12345.mov` ❌ No device ID
- These will only appear in "Show All Devices" mode
- This is expected behavior

**New videos** (uploaded after this fix) will have device IDs:
- Format: `MyRef-1234567890-abc12345_ABC12345.mov` ✅ Has device ID
- These will appear in device-specific view

## Troubleshooting

### Problem: Videos still don't appear in history

**Check 1: Device ID**
```swift
print(DeviceIdentifierService.shared.shortDeviceIdentifier)
// Should print: "ABC12345" (8 characters)
```

**Check 2: Worker deployed**
- Verify your Cloudflare Worker has the updated code
- Check worker logs for the new filename format

**Check 3: Manual test**
- Tap logo 10 times to unlock "Show All Devices"
- If videos appear now, device ID isn't in the filename
- Re-deploy worker and upload a new test video

### Problem: "Show All Devices" doesn't show anything

This means the fetch is failing. Check:
```
❌ Failed to fetch videos: <error message>
```

### Problem: Some videos appear, others don't

This is normal if:
- Old videos don't have device IDs
- Videos were uploaded from different devices
- Solution: Use "Show All Devices" mode

## Example Filename Formats

### Old (before fix):
```
MyReference-1732099200000-a1b2c3d4.mov
```
- Reference: MyReference
- Timestamp: 1732099200000
- Random ID: a1b2c3d4
- Device ID: ❌ Missing

### New (after fix):
```
MyReference-1732099200000-a1b2c3d4_ABC12345.mov
```
- Reference: MyReference
- Timestamp: 1732099200000
- Random ID: a1b2c3d4
- Device ID: ABC12345 ✅

## Benefits of This Approach

✅ **Clear separation** - Device ID is a distinct field, not buried in filename
✅ **Worker control** - Worker can choose how to use the device ID
✅ **Backward compatible** - Old videos without device ID still work
✅ **Easy to filter** - Simple string matching on `_ABC12345` pattern
✅ **Human readable** - You can see device ID in filename at a glance

## Next Steps

After deploying:
1. Upload a test video
2. Check the debug logs
3. Verify it appears in history
4. Upload from another device (if available)
5. Verify device filtering works
6. Test "Show All Devices" toggle

If issues persist, check the debug output and share it for further troubleshooting!
