// =====================================================
// CLOUDFLARE WORKER CODE - Video Upload with EmailJS
// FIXED: Now uses private key for server-side calls
// =====================================================

export default {
  async fetch(request, env) {
    // ============= CORS HEADERS =============
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-API-Key',
    };

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    // ============= AUTHENTICATION =============
    const apiKey = request.headers.get('X-API-Key');
    if (!apiKey || apiKey !== env.API_KEY) {
      return new Response(JSON.stringify({
        error: 'Unauthorized',
        message: 'Invalid or missing API key'
      }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // ============= ROUTE HANDLING =============
    const url = new URL(request.url);
    
    // GET /list - List all videos
    if (request.method === 'GET' && url.pathname === '/list') {
      return handleListVideos(env, corsHeaders);
    }

    // DELETE /delete/:fileId - Delete a video
    if (request.method === 'DELETE' && url.pathname.startsWith('/delete/')) {
      const fileId = url.pathname.replace('/delete/', '');
      return handleDeleteVideo(fileId, env, corsHeaders);
    }

    // ============= METHOD CHECK FOR UPLOAD =============
    if (request.method !== 'POST') {
      return new Response(JSON.stringify({
        error: 'Method not allowed'
      }), {
        status: 405,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    try {
      // Parse form data
      const formData = await request.formData();
      const file = formData.get('video') || formData.get('file'); // Accept both field names
      const reference = formData.get('reference');
      const deviceId = formData.get('deviceId');
      
      // Validate inputs
      if (!file) {
        return new Response(JSON.stringify({
          error: 'No file provided'
        }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      if (!reference || reference.trim() === '') {
        return new Response(JSON.stringify({
          error: 'No reference number provided'
        }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      // Validate file size (100 MB limit)
      const maxSize = 100 * 1024 * 1024;
      if (file.size > maxSize) {
        return new Response(JSON.stringify({
          error: 'File too large',
          message: 'File must be under 100 MB'
        }), {
          status: 413,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      // Get original file extension (supports .mp4, .mov, .jpg, .jpeg, .png, .zip)
      const originalFileName = file.name || 'upload';
      const fileExt = originalFileName.split('.').pop() || 'bin';
      
      // Generate unique filename with collision detection
      const sanitizedReference = reference.trim().replace(/[^a-zA-Z0-9-_]/g, '-');
      const fileName = await generateUniqueFileName(env, sanitizedReference, deviceId, fileExt);
      
      console.log(`📁 Generated filename: ${fileName} (extension: ${fileExt})`);

      // Determine content type based on extension
      const contentTypes = {
        'mp4': 'video/mp4',
        'mov': 'video/quicktime',
        'm4v': 'video/x-m4v',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'zip': 'application/zip'
      };
      const contentType = contentTypes[fileExt.toLowerCase()] || 'application/octet-stream';

      // Upload to R2 with correct content type
      await env.VIDEO_BUCKET.put(fileName, file.stream(), {
        httpMetadata: {
          contentType: contentType,
        },
        customMetadata: {
          uploadedAt: new Date().toISOString(),
          fileSize: file.size.toString(),
          reference: reference.trim(),
          fileType: fileExt,
        }
      });

      // Generate download URL
      const downloadURL = `${env.PUBLIC_DOMAIN}/${fileName}`;

      // ============= SEND EMAIL =============
      let emailSent = false;
      let emailError = null;

      try {
        console.log('📧 Sending email notification...');
        console.log('Using private key for server-side API call');
        
        // Determine file type for email
        const fileTypeLabel = ['mp4', 'mov', 'm4v'].includes(fileExt.toLowerCase()) ? 'Video' : 
                             ['jpg', 'jpeg', 'png'].includes(fileExt.toLowerCase()) ? 'Photo' :
                             fileExt.toLowerCase() === 'zip' ? 'Photos (ZIP)' : 'File';
        
        // Build email payload with PRIVATE KEY (required for server-side calls)
        const emailPayload = {
          service_id: 'service_uhfejsl',
          template_id: 'template_7ygd3fr',
          user_id: 'cB2IeD1LQI51b-1sG',
          accessToken: 'ikTPdrdf2iy8GbHqHy7X_',  // CRITICAL: Private key for server-side calls
          template_params: {
            reference: reference.trim(),
            video_link: downloadURL,
            upload_date: new Date().toLocaleString('en-US', {
              dateStyle: 'medium',
              timeStyle: 'short'
            }),
            file_size: formatBytes(file.size),
            file_type: fileTypeLabel, // NEW: Include file type in email
          }
        };

        console.log('EmailJS payload:', {
          service_id: emailPayload.service_id,
          template_id: emailPayload.template_id,
          user_id: emailPayload.user_id,
          has_accessToken: true,
          params: emailPayload.template_params
        });

        const emailResponse = await fetch('https://api.emailjs.com/api/v1.0/email/send', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(emailPayload)
        });

        const emailResponseText = await emailResponse.text();
        
        console.log('EmailJS Response:', {
          status: emailResponse.status,
          statusText: emailResponse.statusText,
          body: emailResponseText
        });

        if (emailResponse.ok) {
          emailSent = true;
          console.log('✅ Email sent successfully');
        } else {
          emailError = `EmailJS error ${emailResponse.status}: ${emailResponseText}`;
          console.error('❌', emailError);
        }

      } catch (error) {
        emailError = error.message;
        console.error('❌ Failed to send email:', error);
      }

      // Return response
      return new Response(JSON.stringify({
        success: true,
        download_url: downloadURL,
        file_id: fileName,
        file_size: file.size,
        uploaded_at: new Date().toISOString(),
        email_sent: emailSent,
        email_error: emailError,
      }), {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          ...corsHeaders,
        },
      });

    } catch (error) {
      console.error('Upload error:', error);
      
      return new Response(JSON.stringify({
        error: 'Upload failed',
        message: error.message
      }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }
  },
};

// ============= LIST VIDEOS HANDLER =============
async function handleListVideos(env, corsHeaders) {
  try {
    console.log('📋 Fetching video list from R2...');
    
    // List all objects in the bucket
    const listed = await env.VIDEO_BUCKET.list({
      limit: 1000, // Maximum videos to return
    });

    // Map R2 objects to a clean response format
    const videos = listed.objects.map(obj => {
      // Get file extension
      const fileExt = obj.key.split('.').pop() || '';
      
      // Parse the filename to extract reference (format: reference-timestamp-uuid.ext)
      const fileNameWithoutExt = obj.key.replace(`.${fileExt}`, '');
      const fileNameParts = fileNameWithoutExt.split('-');
      const reference = fileNameParts.slice(0, -2).join('-'); // Everything except timestamp and uuid
      
      return {
        file_id: obj.key,
        reference: obj.customMetadata?.reference || reference,
        download_url: `${env.PUBLIC_DOMAIN}/${obj.key}`,
        file_size: obj.size,
        uploaded_at: obj.customMetadata?.uploadedAt || obj.uploaded.toISOString(),
        file_name: obj.key,
      };
    });

    // Sort by upload date, newest first
    videos.sort((a, b) => new Date(b.uploaded_at) - new Date(a.uploaded_at));

    console.log(`✅ Found ${videos.length} videos`);

    return new Response(JSON.stringify({
      success: true,
      count: videos.length,
      videos: videos,
    }), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        ...corsHeaders,
      },
    });

  } catch (error) {
    console.error('❌ List videos error:', error);
    
    return new Response(JSON.stringify({
      error: 'Failed to list videos',
      message: error.message
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

// ============= DELETE VIDEO HANDLER =============
async function handleDeleteVideo(fileId, env, corsHeaders) {
  try {
    console.log(`🗑️ Attempting to delete video: ${fileId}`);
    
    // Validate fileId
    if (!fileId || fileId.trim() === '') {
      return new Response(JSON.stringify({
        error: 'Invalid file ID',
        message: 'File ID cannot be empty'
      }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Check if file exists
    const existingFile = await env.VIDEO_BUCKET.head(fileId);
    
    if (!existingFile) {
      return new Response(JSON.stringify({
        error: 'File not found',
        message: `Video ${fileId} does not exist`
      }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Delete the file from R2
    await env.VIDEO_BUCKET.delete(fileId);
    
    console.log(`✅ Successfully deleted video: ${fileId}`);

    return new Response(JSON.stringify({
      success: true,
      message: 'Video deleted successfully',
      file_id: fileId,
      deleted_at: new Date().toISOString(),
    }), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        ...corsHeaders,
      },
    });

  } catch (error) {
    console.error('❌ Delete video error:', error);
    
    return new Response(JSON.stringify({
      error: 'Failed to delete video',
      message: error.message
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

// ============= HELPER: GENERATE UNIQUE FILENAME =============
async function generateUniqueFileName(env, sanitizedReference, deviceId, fileExt) {
  // Build base filename
  const deviceSuffix = (deviceId && deviceId.trim() !== '') ? `_${deviceId.trim()}` : '';
  const baseFileName = `${sanitizedReference}${deviceSuffix}.${fileExt}`;
  
  // Check if base filename exists
  const existingFile = await env.VIDEO_BUCKET.head(baseFileName);
  if (!existingFile) {
    console.log(`✅ Using base filename: ${baseFileName}`);
    return baseFileName;
  }
  
  // File exists, find next available number
  console.log(`⚠️ Collision detected for ${baseFileName}, finding next available...`);
  let counter = 2;
  while (counter < 1000) { // Safety limit to prevent infinite loops
    const numberedFileName = `${sanitizedReference}-${counter}${deviceSuffix}.${fileExt}`;
    const exists = await env.VIDEO_BUCKET.head(numberedFileName);
    if (!exists) {
      console.log(`✅ Using numbered filename: ${numberedFileName}`);
      return numberedFileName;
    }
    counter++;
  }
  
  // Fallback to UUID if we somehow hit 1000 collisions
  const fallbackFileName = `${sanitizedReference}-${crypto.randomUUID().substring(0, 8)}${deviceSuffix}.${fileExt}`;
  console.log(`⚠️ Too many collisions, using UUID fallback: ${fallbackFileName}`);
  return fallbackFileName;
}

function formatBytes(bytes) {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
}
