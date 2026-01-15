ASSUME_ROLE_OUTPUT=$(aws sts assume-role --role-arn $ROLE_TO_ASSUME --role-session-name DeleteDynamoDBSession)
export AWS_ACCESS_KEY_ID=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.SessionToken')



#########################################################################
# CREATE DEPENDENCY RESOURCES/INFRASTRUCTURE
#########################################################################
# This creates a data object that contains some useful info, like account id which is used later in the code
data "aws_caller_identity" "current" {}

# This creates a data object that contains the current region name
data "aws_region" "current" {}

# This creates a source code repository
resource "aws_codecommit_repository" "codepipeline_source" {
  repository_name = "cc-repo"
  default_branch  = "master"
}

# This creates an s3 bucket, where various AWS services (as well as the user) can store data - for example codepipeline
resource "aws_s3_bucket" "artifacts_bucket" {
  bucket = join("", [var.base_name, "artifacts-bucket"])
}
# This creates an Elastic Container Registry - storage for container images
resource "aws_ecr_repository" "source_container_repository" {
  name = "container-repository"
  encryption_configuration {
    encryption_type = "AES256"
  }

}
