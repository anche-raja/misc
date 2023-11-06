const AWS = require('aws-sdk');
const crypto = require('crypto');
const fs = require('fs');
const zlib = require('zlib');
const { promisify } = require('util');
const stream = require('stream');

const pipeline = promisify(stream.pipeline);

// Initialize S3 client
const s3 = new AWS.S3();

// Function to create a gzip file
async function createGzipFile(content, filePath) {
  await pipeline(
    stream.Readable.from(content),
    zlib.createGzip(),
    fs.createWriteStream(filePath)
  );
}

// Function to calculate MD5 hash of the file
function calculateMD5(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('md5');
    const stream = fs.createReadStream(filePath);
    stream.on('data', data => hash.update(data));
    stream.on('end', () => resolve(hash.digest('hex')));
    stream.on('error', reject);
  });
}

// Function to upload file to S3
async function uploadFileToS3(bucketName, key, localFilePath) {
  const fileStream = fs.createReadStream(localFilePath);
  const fileMD5 = await calculateMD5(localFilePath);
  const params = {
    Bucket: bucketName,
    Key: key,
    Body: fileStream,
    ContentMD5: Buffer.from(fileMD5, 'hex').toString('base64'),
  };
  return s3.upload(params).promise();
}

// Your local file and S3 details
const content = 'Your content to gzip and upload';
const localFilePath = '/path/to/your/file.gz';
const bucketName = 'your-bucket-name';
const s3Key = 'your-file.gz';

// Create a gzip file, calculate MD5, upload to S3, and verify MD5 hash
async function executeUpload() {
  try {
    // Create a gzip file locally
    await createGzipFile(content, localFilePath);

    // Upload file to S3
    const s3Response = await uploadFileToS3(bucketName, s3Key, localFilePath);

    // Compare local MD5 hash with the ETag from S3
    const localFileMD5 = await calculateMD5(localFilePath);
    const s3ETag = s3Response.ETag.replace(/"/g, ''); // S3 ETag contains quotes

    if (localFileMD5 === s3ETag) {
      console.log('Success! MD5 hash matches with S3 ETag.');
    } else {
      console.warn('Warning: MD5 hash does not match S3 ETag.');
    }
  } catch (error) {
    console.error('An error occurred:', error);
  }
}

executeUpload();
