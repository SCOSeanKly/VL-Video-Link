//
//  CLOUDFLARE_WORKER_NOTES.swift
//  VM
//
//  Cloudflare Worker Requirements for Photo Support
//  Created by Assistant on 21/11/2025.
//

/*
 
 CLOUDFLARE WORKER UPDATES NEEDED
 =================================
 
 Your Cloudflare Worker at:
 https://video-uploader.ske-d03.workers.dev/upload
 
 Should already work with photos and zips, but here are the key points:
 
 
 1. FILE TYPE DETECTION
 ----------------------
 
 The worker receives files with different extensions:
 - Videos: .mp4, .mov, .m4v
 - Photos: .jpg, .jpeg, .png
 - Archives: .zip
 
 Make sure your worker:
 ✓ Doesn't enforce video-only mime types
 ✓ Preserves the original file extension
 ✓ Stores files with correct Content-Type headers
 
 
 2. MULTIPART FORM DATA
 ----------------------
 
 Your iOS app sends:
 ```
 Content-Type: multipart/form-data; boundary=...
 X-API-Key: sk_a8d9f7b2c4e1x6z3
 
 Parts:
 - file: [binary data] (name varies: video, file, etc.)
 - reference: [string]
 - deviceId: [string]
 ```
 
 
 3. RESPONSE FORMAT
 ------------------
 
 Worker should return (same for all file types):
 ```json
 {
   "download_url": "https://your-r2.workers.dev/filename.ext",
   "file_id": "unique-id",
   "expires_at": "2025-12-21T00:00:00Z",
   "email_sent": true,
   "email_error": null
 }
 ```
 
 
 4. R2 STORAGE
 -------------
 
 When storing to Cloudflare R2:
 
 ```javascript
 // Get the file extension from the filename
 const fileExt = filename.split('.').pop();
 
 // Set appropriate Content-Type
 const contentTypes = {
   'mp4': 'video/mp4',
   'mov': 'video/quicktime',
   'jpg': 'image/jpeg',
   'jpeg': 'image/jpeg',
   'png': 'image/png',
   'zip': 'application/zip'
 };
 
 const contentType = contentTypes[fileExt] || 'application/octet-stream';
 
 // Store to R2 with correct headers
 await env.MY_BUCKET.put(filename, fileData, {
   httpMetadata: {
     contentType: contentType
   }
 });
 ```
 
 
 5. EXAMPLE WORKER CODE
 ----------------------
 
 ```javascript
 export default {
   async fetch(request, env) {
     if (request.method !== 'POST') {
       return new Response('Method not allowed', { status: 405 });
     }
 
     // Check API key
     const apiKey = request.headers.get('X-API-Key');
     if (apiKey !== 'sk_a8d9f7b2c4e1x6z3') {
       return new Response('Unauthorized', { status: 401 });
     }
 
     // Parse multipart form data
     const formData = await request.formData();
     const file = formData.get('video') || formData.get('file');
     const reference = formData.get('reference');
     const deviceId = formData.get('deviceId');
 
     if (!file) {
       return new Response('No file uploaded', { status: 400 });
     }
 
     // Generate filename (preserve extension)
     const originalName = file.name;
     const fileExt = originalName.split('.').pop();
     const filename = `${Date.now()}_${deviceId}.${fileExt}`;
 
     // Determine content type
     const contentTypes = {
       'mp4': 'video/mp4',
       'mov': 'video/quicktime',
       'jpg': 'image/jpeg',
       'jpeg': 'image/jpeg',
       'png': 'image/png',
       'zip': 'application/zip'
     };
     const contentType = contentTypes[fileExt] || 'application/octet-stream';
 
     // Upload to R2
     const fileData = await file.arrayBuffer();
     await env.MY_BUCKET.put(filename, fileData, {
       httpMetadata: {
         contentType: contentType
       },
       customMetadata: {
         reference: reference || '',
         deviceId: deviceId || '',
         uploadedAt: new Date().toISOString()
       }
     });
 
     // Generate download URL
     const downloadUrl = `https://your-r2-domain.workers.dev/${filename}`;
 
     // Optional: Send email notification
     let emailSent = false;
     let emailError = null;
     
     try {
       // Your email sending logic here
       emailSent = true;
     } catch (error) {
       emailError = error.message;
     }
 
     // Return response
     return new Response(JSON.stringify({
       download_url: downloadUrl,
       file_id: filename,
       expires_at: null,
       email_sent: emailSent,
       email_error: emailError
     }), {
       headers: {
         'Content-Type': 'application/json'
       }
     });
   }
 };
 ```
 
 
 6. KEY CHANGES FROM VIDEO-ONLY
 -------------------------------
 
 ✓ Accept 'file' or 'video' form field name
 ✓ Don't hardcode .mp4 extension
 ✓ Use file's actual extension
 ✓ Set correct Content-Type based on extension
 ✓ Don't validate mime type (accept all file types)
 
 
 7. TESTING
 ----------
 
 Test with:
 - Single video (.mp4, .mov)
 - Single photo (.jpg)
 - Multiple photos (.zip)
 
 Verify:
 ✓ Correct file extension in download URL
 ✓ Files download with correct mime type
 ✓ ZIP files can be extracted
 ✓ Reference numbers are stored
 
 
 If your worker already accepts any file type and preserves extensions,
 no changes are needed!
 
 */
