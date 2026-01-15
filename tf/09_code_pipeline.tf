
#########################################################################
# CREATE CODEPIPELINE RESOURCES
#########################################################################....
data "aws_iam_policy" "codepipeline_access" {
  arn = "arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess"
}

data "aws_iam_policy" "codepipeline_codecommit_access" {
  arn = "arn:aws:iam::aws:policy/AWSCodeCommitFullAccess"
}

data "aws_iam_policy" "codepipeline_s3_access" {
  arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role" "container_codepipeline_role" {
  name = "codepipeline_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = "AllowCodepipelineAssume"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_pipeline_access" {
  role       = aws_iam_role.container_codepipeline_role.name
  policy_arn = data.aws_iam_policy.codepipeline_access.arn
}

resource "aws_iam_role_policy_attachment" "codepipeline_codecommit_access" {
  role       = aws_iam_role.container_codepipeline_role.name
  policy_arn = data.aws_iam_policy.codepipeline_codecommit_access.arn
}

resource "aws_iam_role_policy_attachment" "codepipeline_s3_access" {
  role       = aws_iam_role.container_codepipeline_role.name
  policy_arn = data.aws_iam_policy.codepipeline_s3_access.arn
}

resource "aws_iam_role_policy_attachment" "codepipeline_codebuild_access" {
  role       = aws_iam_role.container_codepipeline_role.name
  policy_arn = data.aws_iam_policy.codebuild_access.arn
}

resource "aws_iam_role_policy_attachment" "codepipeline_codedeploy_access" {
  role       = aws_iam_role.container_codepipeline_role.name
  policy_arn = data.aws_iam_policy.codedeploy_access.arn
}

resource "aws_codepipeline" "container_pipeline" {
  name     = "container-pipeline"
  role_arn = aws_iam_role.container_codepipeline_role.arn
  artifact_store {
    location = aws_s3_bucket.artifacts_bucket.bucket
    type     = "S3"
  }
  stage {
    name = "Source"
    action {
      name             = "Download-Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      output_artifacts = ["SourceOutput"]
      configuration = {
        RepositoryName       = aws_codecommit_repository.codepipeline_source.repository_name
        BranchName           = "master"
        PollForSourceChanges = "true"
      }
      version = "1"
    }
  }
  # stage {
  #   name = "InfraBuild"
  #   action {
  #     name             = "Petclinc-Infra-Creation"
  #     category         = "Build"
  #     owner            = "AWS"
  #     provider         = "CodeBuild"
  #     input_artifacts  = ["SourceOutput"]
  #     configuration = {
  #       ProjectName = aws_codebuild_project.container_pipeline_codebuild_project_infrastructure.id
  #     }
  #     version = "1"
  #   }
  # }
  stage {
    name = "Build"
    action {
      name             = "Petclinic-Build-Action"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      configuration = {
        ProjectName = aws_codebuild_project.container_pipeline_codebuild_project.id
      }
      version = "1"
    }
  }
  # stage {
  #   name = "Deploy"
  #   action {
  #     name            = "Petclinic-Deploy-Action"
  #     category        = "Deploy"
  #     owner           = "AWS"
  #     provider        = "CodeDeploy"
  #     input_artifacts = ["BuildOutput"]      
  #     configuration = {
  #       ApplicationName     = aws_codedeploy_app.codedeploy_container_application.name
  #       DeploymentGroupName = aws_codedeploy_deployment_group.container_deployment_group.deployment_group_name
  #     }
  #     version = "1"
  #   }
  # }

  // Added new Test Stage for Test automation 
  stage {
    name = "Test"
    action {
      name = "PetClinic-Test-Action"
      category = "Test"
      owner = "AWS"
      provider = "CodeBuild"      
      input_artifacts = ["BuildOutput"]
      output_artifacts = ["TestResults"]     // Test Results will be pushed to S3 
      configuration = {
         ProjectName = aws_codebuild_project.container_pipeline_codebuild_project_test.id
      }
       version = "1"
    }
  }
  
}

