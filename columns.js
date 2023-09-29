const AWS = require("aws-sdk");
const costexplorer = new AWS.CostExplorer({ region: "us-east-1" });
const fs = require('fs');
const s3 = new AWS.S3();

exports.handler = async (event) => {
    const services = [
        "Amazon Relational Database Service",
        "Amazon Elastic Container Service",
        "Amazon Elastic Container Registry",
        "Amazon Elastic Compute Cloud",
        "Amazon Simple Storage Service",
        "AWS CodeDeploy",
        "AWS CodeBuild",
        "AWS CodeCommit",
        "Amazon Virtual Private Cloud",
        "IAM"
    ];

    let combinedResponse = [];

    for (let service of services) {
        const params = {
            TimePeriod: {
                Start: "2023-09-20",
                End: "2023-09-25"
            },
            Granularity: "DAILY",
            Filter: {
                Dimensions: {
                    Key: "SERVICE",
                    Values: [service],
                }
            },
            GroupBy: [{
                Type: "DIMENSION",
                Key: "USAGE_TYPE"
            }],
            Metrics: ["BlendedCost", "UnblendedCost", "UsageQuantity"]
        };

        try {
            const response = await costexplorer.getCostAndUsage(params).promise();
            combinedResponse.push(...response.ResultsByTime);
        } catch (error) {
            console.error(`Error fetching cost data for ${service}:`, error);
            throw error;
        }
    }

    const csvContent = writeToCSV(combinedResponse);
    const filePath = '/tmp/data.csv';
    fs.writeFileSync(filePath, csvContent);

    const bucketName = 'q3-cc-db-remote-state';
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
    const header = ["Date Start", "Date End", "Usage Type", "Blended Cost", "Unblended Cost", "Usage Quantity", "Unit"];
    let csvContent = header.join(",") + "\n";

    data.forEach(timePeriod => {
        const startDate = timePeriod.TimePeriod.Start;
        const endDate = timePeriod.TimePeriod.End;

        timePeriod.Groups.forEach(group => {
            const usageType = group.Keys[0];
            const blendedCost = parseFloat(group.Metrics.BlendedCost.Amount).toFixed(2);
            const unblendedCost = parseFloat(group.Metrics.UnblendedCost.Amount).toFixed(2);
            const usageQuantity = parseFloat(group.Metrics.UsageQuantity.Amount).toFixed(2);
            const unit = group.Metrics.UsageQuantity.Unit;

            csvContent += [startDate, endDate, usageType, blendedCost, unblendedCost, usageQuantity, unit].join(",") + "\n";
        });
    });

    return csvContent;
};
