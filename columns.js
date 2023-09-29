const AWS = require("aws-sdk");
const costexplorer = new AWS.CostExplorer({ region: "us-east-1" }); // Cost Explorer API operations are currently available in the US East (N. Virginia) region only
const fs = require('fs');
const s3 = new AWS.S3();
exports.handler = async (event) => {

const  params ={
  "TimePeriod": {
    "Start":"2023-09-20",
    "End": "2023-09-25"
  },
  "Granularity": "DAILY",
  "Filter": {      
    "Dimensions": {
      "Key": "SERVICE",
        "Values": ["Amazon Relational Database Service"],
    }
  },
  "GroupBy":[
    {
      "Type":"DIMENSION",
      "Key":"USAGE_TYPE"
    }
  ],
   "Metrics":["BlendedCost", "UnblendedCost", "UsageQuantity"]
}
  try {
    const response = await costexplorer.getCostAndUsage(params).promise();
    //console.log(response);

    // Process and format the response if needed

    await displayAsTable(response);
    //console.log(formatIntoColumns(response));
    const csvContent = writeToCSV(response);

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

    //return true;
  } catch (error) {
    console.error(`Error fetching cost data:`, error);
    throw error;
  }
};



const displayAsTable = (data) => {
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
        "Date Start".padEnd(colWidths[0]),
        "Date End".padEnd(colWidths[1]),
        "Usage Type".padEnd(colWidths[2]),
        "Blended Cost".padEnd(colWidths[3]),
        "Unblended Cost".padEnd(colWidths[4]),
        "Usage Quantity".padEnd(colWidths[5]),
        "Unit".padEnd(colWidths[6])
    ];
    const divider = header.map(title => "-".repeat(title.length)).join(" | ");
    
    data.ResultsByTime.forEach(timePeriod => {
        const startDate = timePeriod.TimePeriod.Start;
        const endDate = timePeriod.TimePeriod.End;

        // Display headers for each day
        console.log(header.join(" | "));
        console.log(divider);

        timePeriod.Groups.forEach(group => {
            const usageType = group.Keys[0].padEnd(colWidths[2]);
            const blendedCost = parseFloat(group.Metrics.BlendedCost.Amount).toFixed(2).padEnd(colWidths[3]);
            const unblendedCost = parseFloat(group.Metrics.UnblendedCost.Amount).toFixed(2).padEnd(colWidths[4]);
            const usageQuantity = parseFloat(group.Metrics.UsageQuantity.Amount).toFixed(2).padEnd(colWidths[5]);
            const unit = group.Metrics.UsageQuantity.Unit.padEnd(colWidths[6]);

            console.log([startDate, endDate, usageType, blendedCost, unblendedCost, usageQuantity, unit].join(" | "));
        });

        console.log(divider);  // print a divider after each day for visual separation
    });
};




const formatIntoColumns = (response) => {
  if (
    !response.ResultsByTime ||
    !response.ResultsByTime[0] ||
    !response.ResultsByTime[0].Groups
  ) {
    return "Invalid data format";
  }

  const groups = response.ResultsByTime[0].Groups;

  // Header row
  let tableString =
    "Usage Type".padEnd(30) +
    "Blended Cost".padEnd(20) +
    "Unblended Cost".padEnd(20) +
    "Usage Quantity".padEnd(20) +
    "\n";
  tableString += "-".repeat(90) + "\n"; // Add a line for clarity

  // Data rows
  for (let group of groups) {
    const usageType = group.Keys[0];
    const blendedCost = group.Metrics.BlendedCost.Amount;
    const unblendedCost = group.Metrics.UnblendedCost.Amount;
    const usageQuantity = group.Metrics.UsageQuantity.Amount;

    tableString +=
      usageType.padEnd(30) +
      blendedCost.padEnd(20) +
      unblendedCost.padEnd(20) +
      usageQuantity.padEnd(20) +
      "\n";
  }

  return tableString;
};


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
