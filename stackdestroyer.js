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



Header:
"Spring Cleaning Your AWS Environment: Automated Cleanup of Stale CloudFormation Stacks"

Introduction:
In the dynamic landscape of cloud computing, resources can quickly become outdated or unnecessary, leading to clutter and increased costs. AWS CloudFormation is a powerful service for managing resources, but it also requires maintenance to remove unused stacks. In this blog, we'll explore an automated solution for identifying and deleting CloudFormation stacks that haven't been updated in over two weeks, ensuring your AWS environment remains optimized and cost-effective.

Why Clean Up Stale Stacks?
Stale CloudFormation stacks can accumulate in your AWS account for various reasons, such as temporary projects, testing environments, or simply forgetting to delete resources after use. These unused stacks can consume resources and contribute to clutter, making management more challenging and potentially incurring unnecessary costs.

Automated Cleanup Solution Overview
Our solution leverages AWS services such as Lambda, EventBridge, and SNS to automate the identification and deletion of stale CloudFormation stacks. We use a two-step process: first, notifying stakeholders about stacks pending deletion, and then, if no updates are made, deleting these stacks after a grace period.

Step 1: Identifying Stale Stacks with AWS Lambda
We start by creating a Lambda function that uses the CloudFormation API to list all stacks and check their last update time. Stacks that haven't been updated for more than two weeks are considered stale and flagged for potential deletion.

Step 2: Notification Before Deletion
Transparency and communication are key in automated processes. We employ Amazon SNS to send email notifications to the team, listing the stacks that are considered stale. This step provides an opportunity for stakeholders to review and update or remove stacks as necessary, ensuring no critical resources are accidentally deleted.

Step 3: The Deletion Process
A second Lambda function runs after the notification period, checking if the previously identified stacks have been updated. If not, it proceeds to delete these stacks, freeing up resources and reducing clutter in the AWS environment.

Scheduling Automation with EventBridge
Amazon EventBridge schedules the Lambda functions, ensuring that the notification and deletion processes run at specified times. This scheduling allows for regular, automated cleanup cycles, maintaining a clean AWS environment with minimal manual intervention.

Conclusion:
Automating the cleanup of stale AWS CloudFormation stacks not only helps in reducing costs but also in maintaining a tidy and efficient cloud environment. By implementing this solution, teams can focus more on innovation and less on manual housekeeping tasks. Remember, automation in cloud resource management is not just about efficiency; it's about fostering a culture of responsibility and optimization.

Final Thoughts
Before implementing this solution, thoroughly test in a non-production environment to ensure it meets your specific needs without impacting essential resources. Always keep stakeholders informed and involved in automated processes affecting resource management.







  Objective
The goal of this process is to maintain an efficient, cost-effective, and tidy AWS environment by automating the identification and deletion of CloudFormation stacks that have not been updated for more than two weeks.

Rationale
Stale CloudFormation stacks can lead to unnecessary costs and resource clutter. Automating their cleanup ensures our AWS environment is optimized and only contains necessary resources.

Components
AWS Lambda: Executes scripts to identify stale stacks and manage notifications and deletions.
Amazon EventBridge: Triggers Lambda functions on a scheduled basis.
Amazon SNS (Simple Notification Service): Sends email notifications to the team regarding stacks pending deletion.
Process Overview
Step 1: Identifying Stale Stacks
A Lambda function (CheckStaleStacksLambda) runs daily to list all CloudFormation stacks and checks their last update time. Stacks not updated in the last two weeks are flagged as stale.

Step 2: Notification Process
Another Lambda function (NotifyTeamLambda) compiles a list of flagged stacks and sends an email notification to the team via Amazon SNS. This allows team members to review and decide on the next steps for these stacks.

Step 3: Deletion Process
If no updates are made to the flagged stacks within a day after the notification, a third Lambda function (DeleteStaleStacksLambda) automatically deletes these stacks, freeing up resources.

Implementation Details
Lambda Functions
CheckStaleStacksLambda: Lists stacks and identifies stale ones based on the last update timestamp.
NotifyTeamLambda: Sends an SNS notification with details of stale stacks.
DeleteStaleStacksLambda: Deletes stacks that remain stale after the notification period.
Amazon EventBridge
Triggers CheckStaleStacksLambda and NotifyTeamLambda functions daily at a specified time.
Triggers DeleteStaleStacksLambda 24 hours after the NotifyTeamLambda function, allowing time for manual review.
Amazon SNS
Used for sending email notifications to a predefined team distribution list.
Subscription confirmation is required for new email addresses.
Schedule
Daily Check: CheckStaleStacksLambda and NotifyTeamLambda run every day at 6 PM UTC.
Deletion Trigger: DeleteStaleStacksLambda runs at 6 PM UTC, 24 hours after the notification is sent.
Permissions & Security
Minimal IAM permissions are assigned to Lambda functions to perform their tasks.
Review and update IAM roles regularly to comply with the principle of least privilege.
Notification Content
Email notifications include:

List of stacks considered for deletion.
Instructions on how to update or exempt stacks from deletion.
Contact information for support.
Action Required
Team members receiving the notification should:

Review the list of flagged stacks.
Update necessary stacks to avoid deletion.
Remove any stacks that are no longer needed.
Support
For assistance or to exclude specific stacks from this process, please contact the cloud operations team at cloud-ops@example.com.
