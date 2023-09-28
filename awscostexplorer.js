const AWS = require("aws-sdk");
const costexplorer = new AWS.CostExplorer({ region: "us-east-1" }); // Cost Explorer API operations are currently available in the US East (N. Virginia) region only

exports.handler = async (event) => {
  const params = {
    TimePeriod: {
      Start: "2023-01-01", // Adjust this based on your requirement
      End: "2023-12-31", // Adjust this based on your requirement
    },
    Granularity: "MONTHLY",
    Filter: {
      And: [
        {
          Dimensions: {
            Key: "SERVICE",
            Values: ["Amazon Relational Database Service"],
          },
        },
      ],
    },
    Metrics: ["BlendedCost"],
    GroupBy: [
      {
        Type: "DIMENSION",
        Key: "USAGE_TYPE",
      },
    ],
  };

  try {
    const response = await costexplorer.getCostAndUsage(params).promise();
    console.log(response);

    // Process and format the response if needed

    return response;
  } catch (error) {
    console.error(`Error fetching cost data:`, error);
    throw error;
  }
};
