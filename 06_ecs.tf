
#########################################################################
# CREATE ECS RESOURCES
#########################################################################
# This creates an Elastic Container Service cluster - used to run services on container infrastructure
resource "aws_ecs_cluster" "container_cluster" {
  name = join("-", [var.base_name, "container_cluster"])
}

# this creates a load balancer for the ECS cluster
resource "aws_lb" "ecs_load_balancer" {
  name               = "ecs-load-balancer"
  load_balancer_type = "application"
  subnets = [
    aws_subnet.public_subnet_a.id,
    aws_subnet.public_subnet_b.id
  ]
  security_groups = [aws_security_group.allow_traffic_from_workspaces.id]
}

# Create load balancer target group - blue
resource "aws_lb_target_group" "ecs_target_group_blue" {
  name        = "ecs-lb-target-group-blue"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.vpc.id
}

# Create load balancer target group - green
resource "aws_lb_target_group" "ecs_target_group_green" {
  name        = "ecs-lb-target-group-green"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.vpc.id
}

# This is the load balancer listener
resource "aws_lb_listener" "ecs_lb_listener_http_80" {
  load_balancer_arn = aws_lb.ecs_load_balancer.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_target_group_blue.arn
  }
}

# This is the load balancer listener
resource "aws_lb_listener" "ecs_lb_listener_http_8080" {
  load_balancer_arn = aws_lb.ecs_load_balancer.arn
  port              = 8080
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_target_group_green.arn
  }
}

# This is where we create the role to be used by the container agent to deploy containers
resource "aws_iam_role" "container_agent_role" {
  name = "container_agent_role"
  assume_role_policy = jsonencode({
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  inline_policy {
    name = "container_agent_policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid = "FullAccess"
          Action = [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          Effect   = "Allow"
          Resource = "*"
        }
      ]
    })
  }
}

#  This is where we create the task definition for the containers to run in ECS
resource "aws_ecs_task_definition" "container_task_definition" {
  family                   = "container_service_task_family"
  cpu                      = 1024
  memory                   = 4096
  container_definitions    = <<TASK_DEFINITION
[
  {
      "name": "cloud-challenge",
      "image": "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/container-repository:latest",
      "portMappings": [
          {
              "name": "cloud-challenge-80-tcp",
              "containerPort": 80,
              "hostPort": 80,
              "protocol": "tcp",
              "appProtocol": "http"
          }
      ],
      "essential": true,
      "environment": [],
      "environmentFiles": [],
      "mountPoints": [],
      "volumesFrom": [],
      "ulimits": [],
      "logConfiguration": {
          "logDriver": "awslogs",
          "options": {
              "awslogs-create-group": "true",
              "awslogs-group": "/ecs/container_service_task_family",
              "awslogs-region": "us-east-1",
              "awslogs-stream-prefix": "ecs"
          },
          "secretOptions": []
      }
  }
]
TASK_DEFINITION
  task_role_arn            = aws_iam_role.container_agent_role.arn
  execution_role_arn       = aws_iam_role.container_agent_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
      tags = {
      Environment = var.environment
      Organization = var.org
      Application = var.project
    }
}


resource "aws_ecs_service" "container_service" {
  depends_on      = [aws_nat_gateway.nat_gateway] # used to delay the creation of the ecs service until the image is available
  name            = "container_service"
  cluster         = aws_ecs_cluster.container_cluster.id
  task_definition = aws_ecs_task_definition.container_task_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  deployment_controller {
    type = "CODE_DEPLOY"
  }
  network_configuration {
    subnets = [
      aws_subnet.public_subnet_a.id,
      aws_subnet.public_subnet_b.id
    ]
    security_groups  = [aws_security_group.allow_traffic_from_load_balancer.id]
    assign_public_ip = true
  }
  load_balancer {
    container_name   = "cloud-challenge"
    container_port   = 80
    target_group_arn = aws_lb_target_group.ecs_target_group_blue.arn
  }
}

resource "aws_appautoscaling_target" "ecs_target" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.container_cluster.name}/${aws_ecs_service.container_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 1
  max_capacity       = 3
}


resource "aws_appautoscaling_policy" "ecs_policy" {
  name               = "ecs-cpu-step-scaling"
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300
    metric_aggregation_type = "Average"
    
    step_adjustment {
      scaling_adjustment          = 1
      metric_interval_lower_bound = 0
    }
  }
}
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "30"  // One time in 30 Secs Average CPU utilization reaches 50%.
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric checks CPU utilization"
  alarm_actions       = [aws_appautoscaling_policy.ecs_policy.arn] 

  dimensions = {
    ClusterName = aws_ecs_cluster.container_cluster.name
    ServiceName = aws_ecs_service.container_service.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "ecs-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "30"
  statistic           = "Average"
  threshold           = "30"  # Trigger when CPU utilization is below 30%.
  alarm_description   = "This metric checks low CPU utilization"
  alarm_actions       = [aws_appautoscaling_policy.ecs_policy_scale_in.arn] 

  dimensions = {
    ClusterName = aws_ecs_cluster.container_cluster.name
    ServiceName = aws_ecs_service.container_service.name
  }
}

resource "aws_appautoscaling_policy" "ecs_policy_scale_in" {
  name               = "ecs-cpu-step-scaling-in"
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300  # 5 minutes cooldown before another scale in can occur.
    metric_aggregation_type = "Average"
    
    step_adjustment {
      scaling_adjustment          = -1  # Decreases the desired count by 1
      metric_interval_upper_bound = 0
    }
  }
}
//================================================================================ 
resource "aws_iam_policy" "rds_auth_policy" {
  name = "rds_auth_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "rds-db:connect"
        ],
        "Resource" : [
          "arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${module.aurora_rds_mysql.cluster_resource_id}/petclinic"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attachment_to_container_agent_role" {
  role       = aws_iam_role.container_agent_role.name
  policy_arn = aws_iam_policy.rds_auth_policy.arn
}



