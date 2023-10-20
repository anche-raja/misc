#########################################################################
# CREATE CODEDEPLOY RESOURCES
#########################################################################
data "aws_iam_policy" "codedeploy_access" {
  arn = "arn:aws:iam::aws:policy/AWSCodeDeployFullAccess"
}

data "aws_iam_policy" "load_balancer_access" {
  arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
}

data "aws_iam_policy" "ecs_access" {
  arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

resource "aws_iam_role" "container_codedeploy_role" {
  name = "codedeploy_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = "AllowDeploybuildAssume"
      Principal = {
        Service = "codedeploy.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_access" {
  role       = aws_iam_role.container_codedeploy_role.name
  policy_arn = data.aws_iam_policy.codedeploy_access.arn
}

resource "aws_iam_role_policy_attachment" "load_balancer_access" {
  role       = aws_iam_role.container_codedeploy_role.name
  policy_arn = data.aws_iam_policy.load_balancer_access.arn
}

resource "aws_iam_role_policy_attachment" "ecs_access" {
  role       = aws_iam_role.container_codedeploy_role.name
  policy_arn = data.aws_iam_policy.ecs_access.arn
}

resource "aws_iam_role_policy_attachment" "codedeploy_s3_access" {
  role       = aws_iam_role.container_codedeploy_role.name
  policy_arn = data.aws_iam_policy.codepipeline_s3_access.arn
}

resource "aws_codedeploy_app" "codedeploy_container_application" {
  compute_platform = "ECS"
  name             = "codedeploy-container-application"
}

resource "aws_codedeploy_deployment_group" "container_deployment_group" {
  app_name               = aws_codedeploy_app.codedeploy_container_application.name
  deployment_group_name  = "ContainerDeploymentGroup"
  service_role_arn       = aws_iam_role.container_codedeploy_role.arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  ecs_service {
    cluster_name = aws_ecs_cluster.container_cluster.name
    service_name = aws_ecs_service.container_service.name
  }
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }
  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [
          "${aws_lb_listener.ecs_lb_listener_http_80.arn}"
        ]
      }
      target_group {
        name = aws_lb_target_group.ecs_target_group_blue.name
      }
      target_group {
        name = aws_lb_target_group.ecs_target_group_green.name
      }
    }
  }
  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }
}
