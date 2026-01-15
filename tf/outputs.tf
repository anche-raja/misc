output "ec2_public_ip" {
  value = aws_instance.docker_server.public_ip
}

output "application_endpoint" {
  value = aws_lb.ecs_load_balancer.dns_name
}

output "image_location" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/container-repository:latest"
}

output "aurora_rds_cluster_resource_id" {
    description = "The RDS Cluster Identifier"
  value = module.aurora_rds_mysql.cluster_resource_id
}
output "aurora_mysql_cluster_endpoint" {
  description = "Writer endpoint for the cluster"
  value       = module.aurora_rds_mysql.cluster_endpoint
}

output "aurora_mysql_cluster_arn" {
  description = "Amazon Resource Name (ARN) of cluster"
  value       = module.aurora_rds_mysql.cluster_arn
}

output "aurora_mysql_master_user_secret" {
  description = "Secret"
  value       = module.aurora_rds_mysql.cluster_master_user_secret
}

