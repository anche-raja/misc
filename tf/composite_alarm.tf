resource "aws_cloudwatch_metric_alarm" "trigger" {
  alarm_name          = "trigger-alarm"
  namespace           = "YourMetricNamespace"  # Replace with your metric's namespace
  metric_name         = "YourMetricName"       # Replace with your metric's name
  comparison_operator = "LessThanOrEqualToThreshold"
  threshold           = 0
  evaluation_periods  = 3     # Check 3 consecutive data points (3 * 3 minutes = 9 minutes total)
  period              = 180    # 3 minutes in seconds
  statistic           = "Sum"  # Sum of the metric values over 3 data points

  # Alarm triggers if the sum of 3 consecutive values is <= 0 (i.e., all 0s)
  datapoints_to_alarm = 3      # Require 3/3 data points to breach
  treat_missing_data  = "missing"  # Adjust based on your use case

  # Optional: Add SNS topic ARN for notifications
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]
}



resource "aws_cloudwatch_metric_alarm" "resolve" {
  alarm_name          = "resolve-alarm"
  namespace           = "YourMetricNamespace"  # Same as above
  metric_name         = "YourMetricName"       # Same as above
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 3
  evaluation_periods  = 3     # Check 3 consecutive data points
  period              = 180    # 3 minutes in seconds
  statistic           = "Sum"  # Sum of the metric values over 3 data points

  # Alarm triggers if the sum of 3 consecutive values is >= 3 (i.e., all 1s)
  datapoints_to_alarm = 3      # Require 3/3 data points to breach
  treat_missing_data  = "missing"

  # Optional: Add SNS topic ARN for notifications
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]
}



resource "aws_cloudwatch_composite_alarm" "main" {
  alarm_name = "composite-alarm"
  alarm_rule = <<EOF
    (ALARM(${aws_cloudwatch_metric_alarm.trigger.arn}))
    AND
    (NOT ALARM(${aws_cloudwatch_metric_alarm.resolve.arn}))
  EOF

  # Optional: Add actions for alarm state changes
  alarm_actions = [aws_sns_topic.alarm_topic.arn]
  ok_actions    = [aws_sns_topic.ok_topic.arn]  # Actions for resolution
}
