const {
  ELBv2Client,
  DescribeLoadBalancersCommand,
  DescribeListenersCommand,
  DescribeRulesCommand,
  DescribeTargetHealthCommand
} = require("@aws-sdk/client-elastic-load-balancing-v2");

const {
  CloudWatchClient,
  PutMetricDataCommand,
} = require("@aws-sdk/client-cloudwatch");

const REGION_EAST = "us-east-1";
const REGION_WEST = "us-west-1";

const elbv2Client = new ELBv2Client({ region: REGION_EAST });
const cloudwatchClient = new CloudWatchClient({ region: REGION_WEST });

exports.handler = async () => {
  const albArn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-app-alb/50dc6c495c0c9188";

  try {
    // Step 1: Get the Load Balancer Details
    const lbRes = await elbv2Client.send(new DescribeLoadBalancersCommand({ LoadBalancerArns: [albArn] }));
    const lb = lbRes.LoadBalancers?.[0];

    if (!lb || lb.State.Code !== "active") {
      console.log("ALB not active or not found.");
      await pushHealthMetric(0);
      return;
    }

    console.log("ALB is active.");

    // Step 2: Get Listeners
    const listenersRes = await elbv2Client.send(new DescribeListenersCommand({ LoadBalancerArn: albArn }));
    const listenerArns = listenersRes.Listeners?.map(listener => listener.ListenerArn) || [];

    if (listenerArns.length === 0) {
      console.log("No listeners found.");
      await pushHealthMetric(0);
      return;
    }

    // Step 3: Get Rules and Target Group ARNs
    const targetGroupArns = [];

    for (const listenerArn of listenerArns) {
      const rulesRes = await elbv2Client.send(new DescribeRulesCommand({ ListenerArn: listenerArn }));
      for (const rule of rulesRes.Rules || []) {
        for (const action of rule.Actions || []) {
          if (action.TargetGroupArn) {
            targetGroupArns.push(action.TargetGroupArn);
          }
        }
      }
    }

    if (targetGroupArns.length === 0) {
      console.log("No target groups found.");
      await pushHealthMetric(0);
      return;
    }

    // Step 4: Check Health of Targets in All Groups
    let allHealthy = true;

    for (const tgArn of targetGroupArns) {
      const targetHealthRes = await elbv2Client.send(new DescribeTargetHealthCommand({ TargetGroupArn: tgArn }));
      const unhealthy = targetHealthRes.TargetHealthDescriptions.some(
        (t) => t.TargetHealth.State !== "healthy"
      );
      if (unhealthy) {
        allHealthy = false;
        break;
      }
    }

    await pushHealthMetric(allHealthy ? 1 : 0);

  } catch (err) {
    console.error("Failed to process:", err);
    await pushHealthMetric(0);
  }
};

// Push health metric to CloudWatch in us-west-1
async function pushHealthMetric(value) {
  try {
    await cloudwatchClient.send(new PutMetricDataCommand({
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
    }));
    console.log("Metric pushed:", value);
  } catch (err) {
    console.error("Failed to push CloudWatch metric:", err);
  }
}
