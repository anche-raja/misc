const AWS = require('aws-sdk');
const fs = require('fs');
const s3 = new AWS.S3();

const writeToCSV = (data) => {
    const colWidths = [
        "Date Start".length,
        "Date End".length,
        "Usage Type".length + 5,
        "Blended Cost".length,
        "Unblended Cost".length,
        "Usage Quantity".length,
        "Unit".length
    ];
    const header = [
        "Date Start",
        "Date End",
        "Usage Type",
        "Blended Cost",
        "Unblended Cost",
        "Usage Quantity",
        "Unit"
    ];
    let csvContent = header.join(",") + "\n";

    data.ResultsByTime.forEach(timePeriod => {
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

exports.handler = async (event) => {
    const data = {
        //... (Your provided JSON data)
    };

    const csvContent = writeToCSV(data);

    // Write the CSV content to a file in the Lambda tmp directory
    const filePath = '/tmp/data.csv';
    fs.writeFileSync(filePath, csvContent);

    // Upload the CSV to S3
    const bucketName = 'your-s3-bucket-name';
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
