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

    let combinedData = [];

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

            response.ResultsByTime.forEach(timePeriod => {
                timePeriod.Groups.forEach(group => {
                    combinedData.push({
                        dateStart: timePeriod.TimePeriod.Start,
                        dateEnd: timePeriod.TimePeriod.End,
                        service: service,
                        usageType: group.Keys[0],
                        blendedCost: parseFloat(group.Metrics.BlendedCost.Amount).toFixed(2),
                        unblendedCost: parseFloat(group.Metrics.UnblendedCost.Amount).toFixed(2),
                        usageQuantity: parseFloat(group.Metrics.UsageQuantity.Amount).toFixed(2),
                        unit: group.Metrics.UsageQuantity.Unit
                    });
                });
            });

        } catch (error) {
            console.error(`Error fetching cost data for ${service}:`, error);
            throw error;
        }
    }

    // Sort by date and service
    combinedData.sort((a, b) => {
        if (a.dateStart !== b.dateStart) return new Date(a.dateStart) - new Date(b.dateStart);
        return a.service.localeCompare(b.service);
    });

    const csvContent = writeToCSV(combinedData);
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
    const header = ["Date Start", "Date End", "Service", "Usage Type", "Blended Cost", "Unblended Cost", "Usage Quantity", "Unit"];
    let csvContent = header.join(",") + "\n";

    data.forEach(entry => {
        csvContent += [entry.dateStart, entry.dateEnd, entry.service, entry.usageType, entry.blendedCost, entry.unblendedCost, entry.usageQuantity, entry.unit].join(",") + "\n";
    });

    return csvContent;
};
