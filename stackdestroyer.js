import * as sns from '@aws-cdk/aws-sns';
import * as subscriptions from '@aws-cdk/aws-sns-subscriptions';

const notificationTopic = new sns.Topic(this, 'StackDeletionTopic', {
  displayName: 'Stack Deletion Notifications',
});

// Subscribe your team's email addresses to the topic
const teamEmails = ['team@example.com']; // Add your team's email addresses here
teamEmails.forEach(email => {
  notificationTopic.addSubscription(new subscriptions.EmailSubscription(email));
});


const notifyLambda = new lambda.Function(this, 'NotifyStackDeletionLambda', {
  runtime: lambda.Runtime.NODEJS_14_X,
  handler: 'notify.handler',
  code: lambda.Code.fromAsset('path/to/your/lambda/notify_code'),
  environment: {
    SNS_TOPIC_ARN: notificationTopic.topicArn,
  },
});

// Grant permission to publish to the SNS topic
notificationTopic.grantPublish(notifyLambda);




const deleteLambda = new lambda.Function(this, 'DeleteStackLambda', {
  runtime: lambda.Runtime.NODEJS_14_X,
  handler: 'delete.handler',
  code: lambda.Code.fromAsset('path/to/your/lambda/delete_code'),
  environment: {
    // Environment variables
  },
});

// Grant necessary permissions to the Lambda function
deleteLambda.addToRolePolicy(new iam.PolicyStatement({
  actions: ['cloudformation:DescribeStacks', 'cloudformation:DeleteStack'],
  resources: ['*'], // Be more specific in production environments
}));


const deleteLambda = new lambda.Function(this, 'DeleteStackLambda', {
  runtime: lambda.Runtime.NODEJS_14_X,
  handler: 'delete.handler',
  code: lambda.Code.fromAsset('path/to/your/lambda/delete_code'),
  environment: {
    // Environment variables
  },
});

// Grant necessary permissions to the Lambda function
deleteLambda.addToRolePolicy(new iam.PolicyStatement({
  actions: ['cloudformation:DescribeStacks', 'cloudformation:DeleteStack'],
  resources: ['*'], // Be more specific in production environments
}));
