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
