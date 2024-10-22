const csv = require('csvtojson');
const fs = require('fs');

// Path to your DynamoDB export CSV file
const csvFilePath = 'path/to/your/dynamodb_export.csv';

// Convert CSV to JSON
csv()
  .fromFile(csvFilePath)
  .then((jsonObj) => {
    // jsonObj is an array of JSON objects converted from CSV
    console.log("CSV data converted to JSON:", jsonObj);

    // Write the JSON object to a file
    fs.writeFileSync('output.json', JSON.stringify(jsonObj, null, 2), 'utf-8');

    console.log('JSON file has been written successfully.');
  })
  .catch((error) => {
    console.error('Error occurred while converting CSV to JSON:', error);
  });
