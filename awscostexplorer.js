const AWS = require("aws-sdk");
const costexplorer = new AWS.CostExplorer({ region: "us-east-1" }); // Cost Explorer API operations are currently available in the US East (N. Virginia) region only

exports.handler = async (event) => {

const   params = {
  "TimePeriod": {
    "Start": "2023-09-20",
    "End": "2023-09-21"
  },
  "Granularity": "DAILY",
  "Filter": {
    "And": [
      {
        "Tags": {
          "Key": "Environment",
          "Values": ["dev"]
        }
      },
      {
        "Tags": {
          "Key": "Application",
          "Values": ["petclinic"]
        }
      },
      {
        "Tags": {
          "Key": "Org",
          "Values": ["CC"]
        }
      },
      {
        "Dimensions": {
          "Key": "SERVICE",
          "Values": ["Amazon Relational Database Service"]
        }
      }
    ]
  },
  "GroupBy": [
    {
      "Type": "DIMENSION",
      "Key": "USAGE_TYPE"
    }
  ],
  "Metrics": ["BlendedCost", "UnblendedCost", "UsageQuantity"]
}

  try {
    const response = await costexplorer.getCostAndUsage(params).promise();
    console.log(response);

    // Process and format the response if needed

    
    console.log(formatIntoColumns(response));
    return true;
  } catch (error) {
    console.error(`Error fetching cost data:`, error);
    throw error;
  }
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

