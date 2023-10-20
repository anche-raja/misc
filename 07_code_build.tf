
#########################################################################
# CREATE CODEBUILD RESOURCES
#########################################################################
data "aws_iam_policy" "codebuild_access" {
  arn = "arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess"
}

data "aws_iam_policy" "codebuild_logs_access" {
  arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

data "aws_iam_policy" "codebuild_ecr_access" {
  arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}
data "aws_iam_policy" "vpc_access" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
data "aws_iam_policy" "admin_access" {
  arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role" "container_codebuild_role" {
  name = "codebuild_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = "AllowCodebuildAssume"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_access" {
  role       = aws_iam_role.container_codebuild_role.name
  policy_arn = data.aws_iam_policy.codebuild_access.arn
}

resource "aws_iam_role_policy_attachment" "codebuild_logs_access" {
  role       = aws_iam_role.container_codebuild_role.name
  policy_arn = data.aws_iam_policy.codebuild_logs_access.arn
}

resource "aws_iam_role_policy_attachment" "codebuild_ecr_access" {
  role       = aws_iam_role.container_codebuild_role.name
  policy_arn = data.aws_iam_policy.codebuild_ecr_access.arn
}

resource "aws_iam_role_policy_attachment" "codebuild_s3_access" {
  role       = aws_iam_role.container_codebuild_role.name
  policy_arn = data.aws_iam_policy.codepipeline_s3_access.arn
}

resource "aws_iam_role_policy_attachment" "codebuild_ecs_access" {
  role       = aws_iam_role.container_codebuild_role.name
  policy_arn = data.aws_iam_policy.ecs_access.arn
}

resource "aws_iam_role_policy_attachment" "codebuild_vpc_access" {
  role       = aws_iam_role.container_codebuild_role.name
  policy_arn = data.aws_iam_policy.admin_access.arn
}

resource "aws_codebuild_project" "container_pipeline_codebuild_project" {
  name         = "container-pipeline-codebuild-project"
  service_role = aws_iam_role.container_codebuild_role.arn
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "RESPOSITORY_URI"
      value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/container-repository:latest"
    }
    environment_variable {
      name  = "TASK_DEFINITION"
      value = aws_ecs_task_definition.container_task_definition.arn
    }
    environment_variable {
      name  = "CONTAINER_NAME"
      value = "cloud-challenge"
    }
    environment_variable {
      name  = "SUBNET_1"
      value = aws_subnet.public_subnet_a.id
    }
    environment_variable {
      name  = "SUBNET_2"
      value = aws_subnet.public_subnet_b.id
    }
    environment_variable {
      name  = "SECURITY_GROUP"
      value = aws_security_group.allow_traffic_from_load_balancer.id
    }
  }
  artifacts {
    type = "CODEPIPELINE"
  }
  source {
    type = "CODEPIPELINE"
  }
  project_visibility = "PRIVATE"

}

// Code Build Project for Test stage .........
resource "aws_codebuild_project" "container_pipeline_codebuild_project_test" {
  name         = "container-pipeline-codebuild-project-test"
  service_role = aws_iam_role.container_codebuild_role.arn
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "APP_URL"
      value = aws_lb.ecs_load_balancer.dns_name
    }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-test.yml"    // spec file for test execution
  }
  artifacts {
    type = "CODEPIPELINE"
  }
  project_visibility = "PRIVATE"
}

# resource "aws_codebuild_project" "container_pipeline_codebuild_project_infrastructure" {
#   name         = "container-pipeline-codebuild-project-infra"
#   service_role = aws_iam_role.container_codebuild_role.arn
#   environment {
#     compute_type    = "BUILD_GENERAL1_SMALL"
#     image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
#     type            = "LINUX_CONTAINER"
#     privileged_mode = true
#   }
#   artifacts {
#     type = "CODEPIPELINE"
#   }
#   source {
#     type      = "CODEPIPELINE"
#     buildspec = "buildspec-infra.yml"
#   }
#   project_visibility = "PRIVATE"

# }



