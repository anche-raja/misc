import json
import gzip
import boto3
from io import BytesIO

s3 = boto3.client('s3')

def lambda_handler(event, context):
    # Your data
    data = {"key": "value"}

    # Convert to JSON string
    json_str = json.dumps(data)

    # Create a gzipped file in memory
    gz_buffer = BytesIO()
    with gzip.GzipFile(mode='w', fileobj=gz_buffer) as gz_file:
        gz_file.write(json_str.encode('utf-8'))

    # Upload the gzipped file to S3
    s3.put_object(
        Bucket='your-bucket-name',
        Key='your-key.gz',
        Body=gz_buffer.getvalue(),
        ContentType='application/gzip'
    )

    return {
        "statusCode": 200,
        "body": json.dumps('File saved to S3 successfully!')
    }
