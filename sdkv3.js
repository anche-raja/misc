import {
  ELBv2Client,
  DescribeLoadBalancersCommand,
  DescribeTargetHealthCommand,
} from "@aws-sdk/client-elastic-load-balancing-v2";

import {
  CloudWatchClient,
  PutMetricDataCommand,
} from "@aws-sdk/client-cloudwatch";

const REGION_EAST = "us-east-1"; // Where ALB lives
const REGION_WEST = "us-west-1"; // Where metric is published

const elbv2Client = new ELBv2Client({ region: REGION_EAST });
const cloudwatchClient = new CloudWatchClient({ region: REGION_WEST });

export const handler = async () => {
  const loadBalancerName = "your-alb-name"; // 👈 change this
  const targetGroupArn = "your-target-group-arn"; // 👈 change this

  try {
    // Step 1: Check ALB state
    const lbRes = await elbv2Client.send(
      new DescribeLoadBalancersCommand({ Names: [loadBalancerName] })
    );

    const lb = lbRes.LoadBalancers?.[0];

    if (!lb || lb.State.Code !== "active") {
      console.log("ALB not active or not found.");
      await pushHealthMetric(0);
      return;
    }

    console.log(`ALB is active.`);

    // Step 2: Check Target Healths
    const targetHealthRes = await elbv2Client.send(
      new DescribeTargetHealthCommand({ TargetGroupArn: targetGroupArn })
    );

    const unhealthy = targetHealthRes.TargetHealthDescriptions.some(
      (t) => t.TargetHealth.State !== "healthy"
    );

    const appHealth = unhealthy ? 0 : 1;

    console.log(`All targets healthy: ${appHealth === 1}`);

    // Step 3: Push metric to us-west-1
    await pushHealthMetric(appHealth);

  } catch (error) {
    console.error("Error checking ALB or targets:", error);
    await pushHealthMetric(0); // default to fail state
  }
};

// Helper to push metric to CloudWatch in us-west-1
async function pushHealthMetric(value) {
  const cmd = new PutMetricDataCommand({
    Namespace: "Custom/ALBHealth",
    MetricData: [
      {
        MetricName: "AppHealthStatus",
        Dimensions: [
          { Name: "SourceRegion", Value: REGION_EAST },
          { Name: "Environment", Value: "prod" },
        ],
        Timestamp: new Date(),
        Value: value,
        Unit: "Count",
      },
    ],
  });

  try {
    await cloudwatchClient.send(cmd);
    console.log(`Metric pushed to ${REGION_WEST} with value: ${value}`);
  } catch (err) {
    console.error("Failed to push metric:", err);
  }
}
