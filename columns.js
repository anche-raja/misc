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
        "AWS Data Transfer",
        "Amazon Virtual Private Cloud",
        "Amazon VPC Subnets",
        "Amazon VPC Security Groups",
        "AWS Identity and Access Management"
    ];
    let combinedResponse = [];

    for (let service of services) {
        const params = {
            //... (same params as before, but with "Values": [service] for the Filter)
            "Filter": {
                "Dimensions": {
                    "Key": "SERVICE",
                    "Values": [service],
                }
            },
        };

        let serviceResponse = await costexplorer.getCostAndUsage(params).promise();
        combinedResponse.push(...serviceResponse.ResultsByTime);
    }

    // Now you have the combinedResponse with data from all services
    const csvContent = writeToCSV(combinedResponse);

    // Write the CSV content to a file in the Lambda tmp directory
    const filePath = '/tmp/data.csv';
    await fs.writeFileSync(filePath, csvContent);

    // Upload the CSV to S3
    const bucketName = 'q3-cc-db-remote-state';
    const key = 'data.csv';  // or any desired path in the bucket
    await s3.putObject({
        Bucket: bucketName,
        Key: key,
        Body: fs.createReadStream(filePath),
        ContentType: 'text/csv'
    }).promise();

    return {
        statusCode: 200,
        body: JSON.stringify({message: 'CSV written to S3 successfully!'}),
    };
};

// ... (the rest of your functions remain unchanged)

// Modify your writeToCSV function to calculate total and average
const writeToCSV = (data) => {
    //... (rest of the code)
    // After processing each service and day:

    // Add Total and Average for all days:
    const totalCost = data.reduce((sum, timePeriod) => {
        return sum + timePeriod.Groups.reduce((groupSum, group) => {
            return groupSum + parseFloat(group.Metrics.BlendedCost.Amount);
        }, 0);
    }, 0);

    const averageCost = totalCost / data.length;
    
    csvContent += `\nTotal Cost for all days: $${totalCost.toFixed(2)}\n`;
    csvContent += `Average Cost per day: $${averageCost.toFixed(2)}\n`;

    return csvContent;
};
