const AWS = require('aws-sdk');
const s3 = new AWS.S3();
const fs = require('fs');
const crypto = require('crypto');

// Calculate MD5 of gzipped content
function calculateMD5(buffer) {
  return crypto.createHash('md5').update(buffer).digest('hex');
}

// Upload the gzipped file to S3 and compare ETag
async function uploadAndVerify(localGzipFilePath, bucketName, key) {
  const gzippedContent = fs.readFileSync(localGzipFilePath);
  const md5Checksum = calculateMD5(gzippedContent);
  
  const uploadParams = {
    Bucket: bucketName,
    Key: key,
    Body: gzippedContent,
    ContentMD5: Buffer.from(md5Checksum, 'hex').toString('base64'),
  };

  try {
    const uploadResponse = await s3.upload(uploadParams).promise();
    const s3ETag = uploadResponse.ETag.replace(/"/g, '');

    if (s3ETag === md5Checksum) {
      console.log('Success! ETag matches MD5 checksum.');
    } else {
      console.log('Mismatch: ETag does not match MD5 checksum.');
    }
  } catch (error) {
    console.error('An error occurred:', error);
  }
}

// Call the uploadAndVerify function with your details
uploadAndVerify('path/to/your/file.gz', 'your-bucket-name', 'your-object-key');
