# Video Aspect Ratio Fix

## Problem
Portrait videos recorded on iPhone were appearing squashed and in landscape orientation when uploaded and played back via the download link. This made vertical videos appear distorted.

## Root Cause
The issue was in `VideoCompressionService.swift`. When compressing videos, the code was incorrectly applying the video's rotation transform to both:
1. The output dimensions (width/height) ❌
2. The video writer input transform ✅

iPhone cameras record ALL videos in landscape orientation at the hardware level. For portrait videos, they add metadata (the `preferredTransform` matrix) that tells video players to rotate the video 90 degrees when displaying it.

### What Was Happening Before:
1. Original video: 1920x1080 (landscape data) with 90° rotation transform
2. Code applied transform to dimensions: 1080x1920 ❌
3. Code wrote 1080x1920 video with 90° transform ❌
4. Result: Video player rotates already-rotated dimensions = squashed video

## Solution
The fix separates the concerns:

1. **For scaling calculations**: Use the display size (after rotation) to determine if the video needs to be scaled down
2. **For output dimensions**: Use the natural (unrotated) size and let the transform handle the rotation
3. **For playback orientation**: Keep the preferredTransform on the writer input so players know how to display it

### Code Changes in `VideoCompressionService.swift`:

#### Before:
```swift
let outputSize = calculateOutputSize(
    from: naturalSize,
    transform: preferredTransform,  // ❌ Was applying rotation to dimensions
    maxDimension: quality.maxDimension
)
```

#### After:
```swift
// Calculate the DISPLAY size (accounting for rotation) for scaling purposes
let displaySize = naturalSize.applying(preferredTransform)
let adjustedSize = CGSize(width: abs(displaySize.width), height: abs(displaySize.height))

// But use NATURAL size for output dimensions (writer will handle rotation via transform)
let outputSize = calculateOutputSize(
    from: naturalSize,  // ✅ Use naturalSize, not transformed size
    maxDimension: quality.maxDimension,
    displaySize: adjustedSize  // ✅ But scale based on display size
)
```

#### Updated `calculateOutputSize` function:
```swift
private func calculateOutputSize(
    from naturalSize: CGSize,
    maxDimension: CGFloat,
    displaySize: CGSize
) -> CGSize {
    // Use the display size (after rotation) to determine if scaling is needed
    let maxDisplaySize = max(displaySize.width, displaySize.height)
    
    var outputSize = naturalSize
    
    // Only scale down if necessary
    if maxDisplaySize > maxDimension {
        let scale = maxDimension / maxDisplaySize
        outputSize.width *= scale
        outputSize.height *= scale
    }
    
    // Round to even numbers (required for H.264 encoding)
    outputSize.width = floor(outputSize.width / 2) * 2
    outputSize.height = floor(outputSize.height / 2) * 2
    
    return outputSize
}
```

## How It Works Now

### For Portrait Videos:
1. Natural size: 1920x1080 (landscape data)
2. Transform: 90° rotation
3. Display size: 1080x1920 (portrait display)
4. Output video: 1920x1080 WITH 90° transform metadata
5. Result: Video players correctly display as portrait ✅

### For Landscape Videos:
1. Natural size: 1920x1080 (landscape data)
2. Transform: 0° (no rotation)
3. Display size: 1920x1080 (landscape display)
4. Output video: 1920x1080 WITH 0° transform
5. Result: Video players correctly display as landscape ✅

## Testing
After applying this fix, test with:
- ✅ Portrait videos (9:16 aspect ratio)
- ✅ Landscape videos (16:9 aspect ratio)
- ✅ Square videos (1:1 aspect ratio)
- ✅ Videos at different compression quality levels

All should maintain their correct aspect ratio and orientation.

## Additional Notes
- This fix applies to all compression quality levels (low, medium, high, original)
- The "original" quality setting uses a different code path (passthrough preset) which already handles orientation correctly
- No changes needed to the Cloudflare Worker - the issue was entirely in the iOS compression logic
