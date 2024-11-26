const AWS = require('aws-sdk');
const kms = new AWS.KMS();

exports.handler = async (event) => {
  try {
    // Extract KeyId from the event or environment variable
    const keyId = event.keyId || process.env.KMS_KEY_ID;

    if (!keyId) {
      throw new Error('KMS Key ID is not provided.');
    }

    console.log(`Enabling KMS key: ${keyId}`);

    // Enable the KMS key
    const result = await kms.enableKey({ KeyId: keyId }).promise();

    console.log(`KMS key enabled successfully: ${keyId}`, result);

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'KMS key enabled successfully',
        keyId: keyId,
      }),
    };
  } catch (error) {
    console.error('Error enabling KMS key:', error);

    return {
      statusCode: 500,
      body: JSON.stringify({
        message: 'Error enabling KMS key',
        error: error.message,
      }),
    };
  }
};
