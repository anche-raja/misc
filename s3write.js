const AWS = require('aws-sdk');
const zlib = require('zlib');
const { Readable } = require('stream');

const s3 = new AWS.S3();

exports.handler = async (event) => {
    // Your data
    const data = JSON.stringify({
        key: 'value'
    });

    // Convert to buffer
    const buffer = Buffer.from(data, 'utf-8');

    // Gzip the buffer
    const gzippedBuffer = zlib.gzipSync(buffer);

    // Create a stream from the gzipped buffer
    const stream = Readable.from(gzippedBuffer);

    // Params for S3 upload
    const uploadParams = {
        Bucket: 'your-bucket-name',
        Key: 'your-key.gz',
        Body: stream,
        ContentType: 'application/gzip'
    };

    try {
        // Upload gzipped file to S3
        const uploadResponse = await s3.upload(uploadParams).promise();
        console.log(`File uploaded successfully at ${uploadResponse.Location}`);
        return {
            statusCode: 200,
            body: JSON.stringify('File saved to S3 successfully!')
        };
    } catch (err) {
        console.log(`An error occurred: ${err}`);
        return {
            statusCode: 500,
            body: JSON.stringify('Failed to save file.')
        };
    }
};


const crypto = require('crypto');
const fs = require('fs');

// Calculate MD5 hash of the file
function calculateMD5(filePath) {
  const fileContent = fs.readFileSync(filePath);
  const hash = crypto.createHash('md5').update(fileContent).digest('hex');
  return hash;
}

const localFilePath = '/path/to/your/file.gz';
const fileMD5 = calculateMD5(localFilePath);



const AWS = require('aws-sdk');
const s3 = new AWS.S3();

async function uploadFileToS3(bucketName, key, localFilePath, fileMD5) {
  const fileContent = fs.readFileSync(localFilePath);
  const params = {
    Bucket: bucketName,
    Key: key,
    Body: fileContent,
    ContentMD5: Buffer.from(fileMD5, 'hex').toString('base64')
  };
  
  try {
    const data = await s3.putObject(params).promise();
    return data.ETag; // The ETag may or may not be the MD5 hash depending on how S3 stores the file.
  } catch (error) {
    console.error("Error uploading file: ", error);
    throw error;
  }
}

// Call the upload function
const bucketName = 'your-bucket-name';
const key = 'your-s3-key-for-the-file.gz';
uploadFileToS3(bucketName, key, localFilePath, fileMD5).then(s3ETag => {
  // Compare ETag with local MD5 hash
  const cleanETag = s3ETag.replace(/"/g, ''); // Remove any quotes from ETag string
  if (cleanETag === fileMD5) {
    console.log("File uploaded successfully and MD5 hashes match.");
  } else {
    console.log("File uploaded, but MD5 hashes do not match!");
  }
});


