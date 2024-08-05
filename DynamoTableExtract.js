const AWS = require('aws-sdk');

// Configure AWS SDK with your region
AWS.config.update({ region: 'us-west-2' });

const dynamodb = new AWS.DynamoDB();

async function getTableSchema(tableName) {
  const params = {
    TableName: tableName
  };

  try {
    const data = await dynamodb.describeTable(params).promise();
    return data.Table;
  } catch (error) {
    console.error("Error describing table:", error);
  }
}

function constructCLIJSON(tableSchema) {
  const cliJSON = {
    TableName: tableSchema.TableName,
    AttributeDefinitions: tableSchema.AttributeDefinitions,
    KeySchema: tableSchema.KeySchema,
    ProvisionedThroughput: {
      ReadCapacityUnits: tableSchema.ProvisionedThroughput.ReadCapacityUnits,
      WriteCapacityUnits: tableSchema.ProvisionedThroughput.WriteCapacityUnits
    },
    GlobalSecondaryIndexes: [],
    LocalSecondaryIndexes: []
  };

  if (tableSchema.GlobalSecondaryIndexes) {
    cliJSON.GlobalSecondaryIndexes = tableSchema.GlobalSecondaryIndexes.map(gsi => ({
      IndexName: gsi.IndexName,
      KeySchema: gsi.KeySchema,
      Projection: gsi.Projection,
      ProvisionedThroughput: {
        ReadCapacityUnits: gsi.ProvisionedThroughput.ReadCapacityUnits,
        WriteCapacityUnits: gsi.ProvisionedThroughput.WriteCapacityUnits
      }
    }));
  }

  if (tableSchema.LocalSecondaryIndexes) {
    cliJSON.LocalSecondaryIndexes = tableSchema.LocalSecondaryIndexes.map(lsi => ({
      IndexName: lsi.IndexName,
      KeySchema: lsi.KeySchema,
      Projection: lsi.Projection
    }));
  }

  return JSON.stringify(cliJSON, null, 2);
}

async function main() {
  const tableName = 'your-table-name';  // Replace with your DynamoDB table name
  const tableSchema = await getTableSchema(tableName);
  const cliJSON = constructCLIJSON(tableSchema);
  console.log(cliJSON);
}

main();
