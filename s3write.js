
const AWS = require('aws-sdk');x
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















const AWS = require('aws-sdk');
const crypto = require('crypto');
const zlib = require('zlib');

// Initialize the S3 client
const s3 = new AWS.S3();

// Function to gzip string content and calculate MD5
function gzipAndHashContent(content) {
  // Gzip string content synchronously
  const gzippedContent = zlib.gzipSync(content);

  // Calculate MD5 hash of gzipped content
  const hash = crypto.createHash('md5').update(gzippedContent).digest('hex');

  // Return gzipped content and its MD5 hash
  return { gzippedContent, hash };
}

// Function to upload gzipped content to S3
function uploadGzipToS3(bucketName, key, gzippedContent, md5Hash) {
  // Convert the MD5 hash to base64
  const base64md5 = Buffer.from(md5Hash, 'hex').toString('base64');

  // Set the parameters for the S3 upload
  const params = {
    Bucket: bucketName,
    Key: key,
    Body: gzippedContent,
    ContentMD5: base64md5,
    // Specify the Content-Encoding to indicate that the content is gzipped
    ContentEncoding: 'gzip',
  };

  // Upload the gzipped content to S3
  s3.upload(params, function(err, data) {
    if (err) {
      console.error('Error uploading to S3:', err);
    } else {
      // The ETag may not match the MD5 hash exactly due to how S3 computes it, especially if multipart upload was used
      console.log('Successfully uploaded to S3:', data);
      // You may want to compare the MD5 hash manually if strict verification is needed
    }
  });
}

// String content to be gzipped and uploaded
const contentToGzip = 'Your string content here';

// S3 details
const bucketName = 'your-bucket-name';
const key = 'your-object-key.gz';

// Gzip the content and calculate MD5
const { gzippedContent, hash } = gzipAndHashContent(contentToGzip);

// Upload the gzipped content to S3
uploadGzipToS3(bucketName, key, gzippedContent, hash);



// Function to calculate MD5 hash from a stream
const calculateMD5FromStream = (stream) => {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('md5');
    stream.on('data', (data) => {
      hash.update(data);
    });
    stream.on('end', () => {
      resolve(hash.digest('hex'));
    });
    stream.on('error', (error) => {
      reject(error);
    });
  });
};



const AWS = require('aws-sdk');

exports.handler = async (event) => {
    // Assuming 'event' contains the 'certificate' data
    const devicesArray = event.certificate;

    const transformedArray = devicesArray.map(item => {
        let caStorageNewValue = '';

        // Extracting the number from caStroage and creating the new value
        const match = item.caStroage.match(/p(\d+)/);
        if (match && match[1]) {
            caStorageNewValue = `CC${match[1]}`;
        }

        return {
            caStartdate: item.caStartdate,
            caEnddate: item.caEnddate,
            caStroage: caStorageNewValue
        };
    });

    console.log(transformedArray);

    // The return value can be used as the response in case of an API Gateway trigger, for example
    return {
        statusCode: 200,
        body: JSON.stringify(transformedArray)
    };
};
