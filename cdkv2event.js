const { Stack, StackProps, Construct } = require('@aws-cdk/core');
const { Function, Runtime, Code } = require('@aws-cdk/aws-lambda');
const { Rule, Schedule } = require('@aws-cdk/aws-events');
const { LambdaFunction } = require('@aws-cdk/aws-events-targets');
const { PolicyStatement } = require('@aws-cdk/aws-iam');

class ScheduledLambdaStack extends Stack {
  constructor(scope, id, props) {
    super(scope, id, props);

    // Create a Lambda function
    const lambdaFn = new Function(this, 'MyLambdaFunction', {
      runtime: Runtime.NODEJS_14_X,
      handler: 'index.handler',
      code: Code.fromAsset('lambda'), // Path to your Lambda function code
    });

    // Allow Lambda to describe CloudFormation stacks (assuming you want to interact with CloudFormation)
    lambdaFn.addToRolePolicy(new PolicyStatement({
      actions: ['cloudformation:DescribeStacks'],
      resources: ['*'], // You can limit this to specific resources if needed
    }));

    // Create an EventBridge rule to trigger the Lambda function every night at 9 PM
    const rule = new Rule(this, 'MyScheduledRule', {
      schedule: Schedule.cron({ minute: '0', hour: '21' }), // Schedule for 9 PM daily
    });

    // Add the Lambda function as a target for the EventBridge rule
    rule.addTarget(new LambdaFunction(lambdaFn));
  }
}

module.exports = { ScheduledLambdaStack };
