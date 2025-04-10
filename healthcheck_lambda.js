const https = require('https');
const AWS = require('aws-sdk');
const cloudwatch = new AWS.CloudWatch();

const albDomain = process.env.ALB_DNS; // DNS name of ALB in us-east-1

exports.handler = async (event) => {
    let healthy = 0;

    try {
        await new Promise((resolve, reject) => {
            const req = https.get(`https://${albDomain}`, res => {
                healthy = res.statusCode === 200 ? 1 : 0;
                resolve();
            });
            req.on('error', reject);
            req.setTimeout(3000, () => req.destroy());
        });
    } catch (e) {
        console.log(`Error checking ALB: ${e.message}`);
    }

    await cloudwatch.putMetricData({
        Namespace: 'CrossRegionHealth',
        MetricData: [{
            MetricName: 'EastAlbHealth',
            Value: healthy,
            Unit: 'None'
        }]
    }).promise();

    return { statusCode: 200 };
};
