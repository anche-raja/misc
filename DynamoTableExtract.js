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

function constructDDL(tableSchema) {
  const tableName = tableSchema.TableName;
  const attributeDefinitions = tableSchema.AttributeDefinitions;
  const keySchema = tableSchema.KeySchema;
  const provisionedThroughput = tableSchema.ProvisionedThroughput;
  const globalSecondaryIndexes = tableSchema.GlobalSecondaryIndexes || [];
  const localSecondaryIndexes = tableSchema.LocalSecondaryIndexes || [];

  const ddl = [];

  // Table definition
  ddl.push(`Table: ${tableName}`);
  ddl.push("Attributes:");
  attributeDefinitions.forEach(attr => {
    ddl.push(`  - ${attr.AttributeName} (${attr.AttributeType})`);
  });

  ddl.push("Key Schema:");
  keySchema.forEach(key => {
    ddl.push(`  - ${key.AttributeName} (${key.KeyType})`);
  });

  ddl.push("Provisioned Throughput:");
  ddl.push(`  - Read Capacity: ${provisionedThroughput.ReadCapacityUnits}`);
  ddl.push(`  - Write Capacity: ${provisionedThroughput.WriteCapacityUnits}`);

  // Global Secondary Indexes
  if (globalSecondaryIndexes.length > 0) {
    ddl.push("Global Secondary Indexes:");
    globalSecondaryIndexes.forEach(gsi => {
      ddl.push(`  - Index Name: ${gsi.IndexName}`);
      ddl.push("    Key Schema:");
      gsi.KeySchema.forEach(key => {
        ddl.push(`      - ${key.AttributeName} (${key.KeyType})`);
      });
      ddl.push("    Projection:");
      const projection = gsi.Projection;
      ddl.push(`      - Projection Type: ${projection.ProjectionType}`);
      if (projection.NonKeyAttributes) {
        ddl.push(`      - Non-Key Attributes: ${projection.NonKeyAttributes.join(', ')}`);
      }
      const gsiThroughput = gsi.ProvisionedThroughput;
      ddl.push("    Provisioned Throughput:");
      ddl.push(`      - Read Capacity: ${gsiThroughput.ReadCapacityUnits}`);
      ddl.push(`      - Write Capacity: ${gsiThroughput.WriteCapacityUnits}`);
    });
  }

  // Local Secondary Indexes
  if (localSecondaryIndexes.length > 0) {
    ddl.push("Local Secondary Indexes:");
    localSecondaryIndexes.forEach(lsi => {
      ddl.push(`  - Index Name: ${lsi.IndexName}`);
      ddl.push("    Key Schema:");
      lsi.KeySchema.forEach(key => {
        ddl.push(`      - ${key.AttributeName} (${key.KeyType})`);
      });
      ddl.push("    Projection:");
      const projection = lsi.Projection;
      ddl.push(`      - Projection Type: ${projection.ProjectionType}`);
      if (projection.NonKeyAttributes) {
        ddl.push(`      - Non-Key Attributes: ${projection.NonKeyAttributes.join(', ')}`);
      }
    });
  }

  return ddl.join('\n');
}

async function main() {
  const tableName = 'your-table-name';  // Replace with your DynamoDB table name
  const tableSchema = await getTableSchema(tableName);
  const ddl = constructDDL(tableSchema);
  console.log(ddl);
}

main();
