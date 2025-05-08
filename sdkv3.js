const {
  ELBv2Client,
  DescribeListenersCommand,
  DescribeRulesCommand,
  DescribeTargetHealthCommand,
} = require("@aws-sdk/client-elastic-load-balancing-v2");

const {
  CloudWatchClient,
  PutMetricDataCommand,
} = require("@aws-sdk/client-cloudwatch");

const REGION_EAST = "us-east-1"; // where ALB lives
const REGION_WEST = "us-west-1"; // where you push the metrics

const elbv2Client = new ELBv2Client({ region: REGION_EAST });
const cloudwatchClient = new CloudWatchClient({ region: REGION_WEST });

// Replace with your actual ALB ARN
const ALB_ARN = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-app-alb/50dc6c495c0c9188";

exports.handler = async () => {
  try {
    // Step 1: Get Listeners
    const listenersRes = await elbv2Client.send(
      new DescribeListenersCommand({ LoadBalancerArn: ALB_ARN })
    );
    const listenerArns = listenersRes.Listeners.map(l => l.ListenerArn);

    // Step 2: Extract Target Group ARNs from Listener Rules
    const targetGroupArns = new Set();

    for (const listenerArn of listenerArns) {
      const rulesRes = await elbv2Client.send(
        new DescribeRulesCommand({ ListenerArn: listenerArn })
      );
      for (const rule of rulesRes.Rules || []) {
        for (const action of rule.Actions || []) {
          if (action.TargetGroupArn) {
            targetGroupArns.add(action.TargetGroupArn);
          }
        }
      }
    }

    if (targetGroupArns.size === 0) {
      console.log("No target groups found.");
      await pushHealthMetric(0);
      return;
    }

    // Step 3: Check Health of All Target Groups
    let allHealthy = true;

    for (const tgArn of targetGroupArns) {
      const targetHealthRes = await elbv2Client.send(
        new DescribeTargetHealthCommand({ TargetGroupArn: tgArn })
      );
      const unhealthy = targetHealthRes.TargetHealthDescriptions.some(
        (desc) => desc.TargetHealth.State !== "healthy"
      );
      if (unhealthy) {
        console.log(`Unhealthy target found in: ${tgArn}`);
        allHealthy = false;
        break;
      }
    }

    await pushHealthMetric(allHealthy ? 1 : 0);
  } catch (err) {
    console.error("Error:", err);
    await pushHealthMetric(0); // On failure, assume unhealthy
  }
};

// Push custom metric to CloudWatch
async function pushHealthMetric(value) {
  try {
    await cloudwatchClient.send(
      new PutMetricDataCommand({
        Namespace: "Custom/ALBHealth",
        MetricData: [{
          MetricName: "AppHealthStatus",
          Dimensions: [
            { Name: "SourceRegion", Value: REGION_EAST },
            { Name: "Environment", Value: "prod" }
          ],
          Timestamp: new Date(),
          Value: value,
          Unit: "Count"
        }]
      })
    );
    console.log("Metric pushed:", value);
  } catch (err) {
    console.error("Failed to push CloudWatch metric:", err);
  }
}
