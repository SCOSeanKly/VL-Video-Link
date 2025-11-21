# Subscription Troubleshooting Guide

## Quick Fixes

### Problem: "Nothing happens when I tap Subscribe"

This is usually caused by one of these issues:

#### 1. **You Already Have an Active Subscription** ⭐ MOST COMMON
   
**How to check:**
- Look at the paywall - does it show "You're Already Subscribed!" banner at the top?
- Check the Debug Info section (in debug builds) - does it say "Subscribed"?

**What's happening:**
StoreKit won't let you purchase a subscription if you already have one active. You need to either:
- **Cancel the existing subscription first**, then purchase again
- **Use "Restore Purchases"** instead of buying again

**How to cancel a sandbox subscription:**

For **Sandbox Testing** (most likely your case):
1. Open **Settings** app
2. Go to **App Store**
3. Scroll down to **SANDBOX ACCOUNT**
4. Tap your test account email
5. Tap **Manage**
6. Find your subscription to `videoLinkMonthly`
7. Tap **Cancel Subscription**

For **TestFlight/Production**:
1. Open **Settings** app
2. Tap your **Apple ID** at the top
3. Tap **Subscriptions**
4. Find your app's subscription
5. Tap **Cancel Subscription**

#### 2. **Sandbox Account Not Signed In**

**Check console logs when you tap Subscribe:**
```
🛒 Starting purchase for product: videoLinkMonthly
```

If you see **nothing** in the console, you're probably not signed into a sandbox account.

**Solution:**
1. Go to Settings → App Store
2. Scroll to **SANDBOX ACCOUNT**
3. Sign in with a sandbox test account (not your real Apple ID!)
4. Try purchasing again

#### 3. **Purchases Disabled on Device**

**Check console logs for:**
```
❌ Client is not allowed to make purchases
❌ Device is not allowed to make payments
```

**Solution:**
1. Settings → Screen Time → Content & Privacy Restrictions
2. Make sure **iTunes & App Store Purchases** is set to **Allow**
3. Or turn off Screen Time entirely

#### 4. **Product Not Loaded**

**Check the paywall:**
- Do you see the subscription card with pricing?
- Or do you see "Unable to Load Subscription" error?

**Solution:**
1. Tap the **Retry** button
2. Check your internet connection
3. Make sure you're using a sandbox account for testing

## Detailed Debugging

### Step 1: Check Console Logs

When you tap "Subscribe to Pro", you should see this sequence in the console:

```
🛒 Starting purchase for product: videoLinkMonthly
⏳ Calling product.purchase()...
```

Then one of:

**✅ SUCCESS:**
```
✅ Got purchase result
✅ Purchase succeeded, verifying transaction...
✅ Transaction verified: 2000000123456789
   Product ID: videoLinkMonthly
   Purchase Date: Nov 21, 2025
⏳ Waiting for StoreKit to update entitlements...
🔍 Checking subscription status...
✅ User is subscribed
✅ Purchase successful and verified
```

**❌ ALREADY SUBSCRIBED:**
```
⚠️ User already has an active subscription!
```

**ℹ️ USER CANCELLED:**
```
ℹ️ User cancelled purchase
```

**❌ ERROR:**
```
❌ Purchase failed with error: ...
   Error domain: ...
   Error code: ...
```

### Step 2: Check Current Subscription Status

In debug builds, you'll see a "Debug Info" section on the paywall showing your current status.

**Possible states:**
- `Unknown` - Status hasn't been checked yet
- `Not Subscribed` - No active subscription
- `Subscribed` - Active subscription
- `Expired` - Subscription expired
- `Grace Period` - Subscription in grace period

### Step 3: Force Refresh Status

If the status looks wrong:
1. Tap "Force Refresh Status" button (debug builds only)
2. Watch the console for detailed logs
3. Check if the status updates correctly

### Step 4: Try Restore Purchases

If you know you have a subscription but the app doesn't recognize it:
1. Tap "Restore Purchases"
2. Wait for it to complete
3. Check if the status updates

## Common Error Codes

### StoreKit Error Codes (SKErrorDomain)

| Code | Meaning | Solution |
|------|---------|----------|
| 2 | Payment Cancelled | User cancelled - no action needed |
| 3 | Client Invalid | Check Screen Time restrictions |
| 4 | Payment Invalid | Product configuration issue |
| 5 | Payment Not Allowed | In-app purchases disabled |

## Testing Scenarios

### Test 1: First-Time Purchase
```
1. Make sure no subscription exists
2. Tap "Subscribe to Pro"
3. Complete purchase flow
4. Should see success and paywall dismisses
```

**Expected console output:**
```
🛒 Starting purchase for product: videoLinkMonthly
✅ Purchase successful and verified
✅ User is subscribed
```

### Test 2: Already Subscribed
```
1. Already have active subscription
2. Tap "Subscribe to Pro"
3. Should see alert/error immediately
```

**Expected console output:**
```
🛒 Starting purchase for product: videoLinkMonthly
⚠️ User already has an active subscription!
```

**Expected UI:**
- Alert showing "You already have an active subscription"
- Or banner at top of paywall

### Test 3: Restore Purchases
```
1. Delete and reinstall app
2. Open paywall
3. Tap "Restore Purchases"
4. Should recognize existing subscription
```

**Expected console output:**
```
✅ Purchases restored
🔍 Checking subscription status...
✅ User is subscribed
```

### Test 4: Expired Subscription
```
1. Let subscription expire (or use expired sandbox test)
2. Open app
3. Should show "not subscribed" status
4. Can purchase new subscription
```

## Sandbox Testing Tips

### Create Multiple Test Accounts
Create several sandbox test accounts in App Store Connect:
- One for active subscriptions
- One for testing new purchases
- One for testing expired subscriptions

### Clear Subscription Between Tests
After testing a purchase, cancel it before testing again:
1. Settings → App Store → Sandbox Account → Manage
2. Cancel the subscription
3. Wait a moment for it to process
4. Test the purchase flow again

### Sandbox Subscription Renewal Times
Sandbox subscriptions renew **much faster** than production:

| Production Duration | Sandbox Duration |
|--------------------|------------------|
| 1 month | 5 minutes |
| 2 months | 10 minutes |
| 3 months | 15 minutes |
| 6 months | 30 minutes |
| 1 year | 1 hour |

Your monthly subscription will renew every **5 minutes** in sandbox!

### Check Transaction History
To see all sandbox transactions:
1. Settings → App Store
2. Tap sandbox account
3. Tap **Manage**
4. View all active and expired subscriptions

## Code Changes Made

### Enhanced Error Handling
- Added check for existing active subscriptions
- Better StoreKit error code handling
- More detailed console logging

### UI Improvements
- Shows "Already Subscribed" banner if applicable
- Debug info section in debug builds
- Force refresh button for troubleshooting
- Better error messages

### Enhanced Logging
All purchase attempts now show:
- Product ID being purchased
- Purchase flow steps
- Transaction verification details
- Error details with domain and code

## Still Having Issues?

### Check Product Configuration
1. Open App Store Connect
2. Go to your app → Features → In-App Purchases
3. Find `videoLinkMonthly`
4. Verify:
   - ✅ Status is "Ready to Submit" or "Approved"
   - ✅ Product ID matches exactly: `videoLinkMonthly`
   - ✅ Pricing is configured
   - ✅ Subscription group exists

### Check App Configuration
In Xcode:
1. Select your app target
2. Go to **Signing & Capabilities**
3. Verify **In-App Purchase** capability is enabled
4. Check that **StoreKit Configuration File** is set (if using local testing)

### Use StoreKit Configuration File
For testing without a sandbox account:

1. In Xcode: File → New → File → StoreKit Configuration File
2. Add your `videoLinkMonthly` product
3. Select your scheme → Edit Scheme
4. Run → Options → StoreKit Configuration
5. Select your configuration file

This lets you test purchases without any Apple ID!

## Quick Checklist

Before reporting a bug, verify:

- [ ] Using a sandbox test account (not production Apple ID)
- [ ] Signed into sandbox account in Settings → App Store
- [ ] In-App Purchases are allowed (Screen Time settings)
- [ ] Product ID is exactly `videoLinkMonthly`
- [ ] Internet connection is working
- [ ] No existing active subscription (or trying to restore, not purchase)
- [ ] Console shows detailed logs when tapping Subscribe
- [ ] App has In-App Purchase capability enabled

## Log Analysis

### What Good Logs Look Like

**App Launch:**
```
🔍 Checking subscription status...
✅ Loaded 1 products
✅ User is subscribed
```

**Successful Purchase:**
```
🛒 Starting purchase for product: videoLinkMonthly
⏳ Calling product.purchase()...
✅ Got purchase result
✅ Purchase succeeded, verifying transaction...
✅ Transaction verified: 2000000789012345
⏳ Waiting for StoreKit to update entitlements...
🔍 Checking subscription status...
🔍 Found transaction for product: videoLinkMonthly
✅ Found matching subscription transaction!
✅ Got subscription status: subscribed
✅ User is subscribed (expires: Dec 21, 2025)
✅ Purchase successful and verified
🛒 Purchase flow completed
```

### What Bad Logs Look Like

**No Sandbox Account:**
```
🛒 Starting purchase for product: videoLinkMonthly
[Nothing else - purchase sheet never appears]
```

**Already Subscribed:**
```
🛒 Starting purchase for product: videoLinkMonthly
⚠️ User already has an active subscription!
🛒 Purchase flow completed
```

**Permission Denied:**
```
🛒 Starting purchase for product: videoLinkMonthly
⏳ Calling product.purchase()...
❌ Purchase failed with error: ...
❌ Client is not allowed to make purchases
```

## Summary

Most subscription issues are caused by:
1. **Already having an active subscription** (can't buy again - use Restore)
2. **Not signed into sandbox account** (no purchase sheet appears)
3. **Purchases disabled** (Screen Time restrictions)

Check the console logs and Debug Info section to diagnose the exact issue!
