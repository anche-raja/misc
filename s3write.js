const AWS = require('aws-sdk');
const fs = require('fs');
const crypto = require('crypto');
const zlib = require('zlib');

// Initialize the S3 client
const s3 = new AWS.S3();

// Function to gzip file content and calculate MD5
function gzipFileSync(inputFilePath) {
  // Read file synchronously
  const fileContent = fs.readFileSync(inputFilePath);

  // Gzip file content synchronously
  const gzippedContent = zlib.gzipSync(fileContent);

  // Calculate MD5 hash of gzipped content
  const hash = crypto.createHash('md5').update(gzippedContent).digest('hex');

  // Return gzipped content and its MD5 hash
  return { gzippedContent, hash };
}

// Function to upload gzipped file to S3
function uploadGzipToS3(bucketName, key, gzippedContent, md5Hash) {
  // Convert the MD5 hash to base64
  const base64md5 = Buffer.from(md5Hash, 'hex').toString('base64');

  // Set the parameters for the S3 upload
  const params = {
    Bucket: bucketName,
    Key: key,
    Body: gzippedContent,
    ContentMD5: base64md5,
  };

  // Upload the gzipped file to S3
  s3.upload(params, function(err, data) {
    if (err) {
      console.error('Error uploading to S3:', err);
    } else {
      console.log('Successfully uploaded to S3:', data);
    }
  });
}

// Local file path
const inputFilePath = 'path/to/your/original/file';

// S3 details
const bucketName = 'your-bucket-name';
const key = 'your-object-key.gz';

// Gzip the file content and calculate MD5
const { gzippedContent, hash } = gzipFileSync(inputFilePath);

// Upload the gzipped file to S3
uploadGzipToS3(bucketName, key, gzippedContent, hash);










const fs = require('fs');
const zlib = require('zlib');
const crypto = require('crypto');

// Function to gzip a string and write it to a file synchronously
function gzipStringToFile(content, outputFilePath) {
  // Convert string to buffer
  const buffer = Buffer.from(content, 'utf-8');

  // Gzip the content
  const gzippedContent = zlib.gzipSync(buffer);

  // Write gzipped content to file
  fs.writeFileSync(outputFilePath, gzippedContent);

  // Calculate MD5 hash of gzipped content
  const hash = crypto.createHash('md5').update(gzippedContent).digest('hex');

  return hash;
}

// Your string content
const content = "The content to be gzipped";

// The output file path
const outputFilePath = "path/to/output/file.gz";

// Gzip the content and get the MD5 hash
const md5Hash = gzipStringToFile(content, outputFilePath);

// Log the MD5 hash
console.log("MD5 Hash:", md5Hash);

