const AWS = require("aws-sdk");
const costexplorer = new AWS.CostExplorer({ region: "us-east-1" });
const fs = require('fs');
const s3 = new AWS.S3();

exports.handler = async (event) => {

    let combinedData = [];

    const params = {
        TimePeriod: {
            Start: "2023-09-20",
            End: "2023-09-25"
        },
        Granularity: "DAILY",
        GroupBy: [
            { Type: "DIMENSION", Key: "SERVICE" },
            { Type: "DIMENSION", Key: "USAGE_TYPE" }
        ],
        Metrics: ["BlendedCost", "UnblendedCost", "UsageQuantity"]
    };

    try {
        const response = await costexplorer.getCostAndUsage(params).promise();

        response.ResultsByTime.forEach(timePeriod => {
            timePeriod.Groups.forEach(group => {
                combinedData.push({
                    dateStart: timePeriod.TimePeriod.Start,
                    dateEnd: timePeriod.TimePeriod.End,
                    service: group.Keys[0],
                    usageType: group.Keys[1],
                    blendedCost: parseFloat(group.Metrics.BlendedCost.Amount).toFixed(2),
                    unblendedCost: parseFloat(group.Metrics.UnblendedCost.Amount).toFixed(2),
                    usageQuantity: parseFloat(group.Metrics.UsageQuantity.Amount).toFixed(2),
                    unit: group.Metrics.UsageQuantity.Unit
                });
            });
        });

    } catch (error) {
        console.error("Error fetching cost data:", error);
        throw error;
    }

    const csvContent = writeToCSV(combinedData);
    const filePath = '/tmp/data.csv';
    fs.writeFileSync(filePath, csvContent);

    const bucketName = 'q3-cc-db-remote-state';  // Modify this to your S3 bucket name
    const key = 'data.csv';

    await s3.putObject({
        Bucket: bucketName,
        Key: key,
        Body: fs.createReadStream(filePath),
        ContentType: 'text/csv'
    }).promise();

    return {
        statusCode: 200,
        body: JSON.stringify({ message: 'CSV written to S3 successfully!' }),
    };
};

const writeToCSV = (data) => {
    const header = ["Date Start", "Date End", "Service", "Usage Type", "Blended Cost", "Unblended Cost", "Usage Quantity", "Unit"];
    let csvContent = header.join(",") + "\n";

    data.forEach(entry => {
        csvContent += [entry.dateStart, entry.dateEnd, entry.service, entry.usageType, entry.blendedCost, entry.unblendedCost, entry.usageQuantity, entry.unit].join(",") + "\n";
    });

    return csvContent;
};
