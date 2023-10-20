module "aurora_rds_mysql" {
  source = "terraform-aws-modules/rds-aurora/aws"

  name                        = join("-", [var.base_name, "db"])
  engine                      = "aurora-mysql"
  engine_mode                 = "provisioned"
  instance_class = "db.serverless"

  master_username             = "root"
  manage_master_user_password = true
  iam_database_authentication_enabled = true
  performance_insights_enabled = true

  instances = {
    one = {
      availability_zone = aws_subnet.private_subnet_a.availability_zone
    }    
  }

  serverlessv2_scaling_configuration = {
    min_capacity = 1
    max_capacity = 5
  }

  vpc_id                 = aws_vpc.vpc.id
  db_subnet_group_name   = aws_db_subnet_group.db-private-subnets.name
  vpc_security_group_ids = [aws_security_group.allow_traffic_from_ecs_container_to_db.id]


  backup_retention_period = 15
  skip_final_snapshot     = true
  storage_encrypted       = true
  apply_immediately       = true
  monitoring_interval     = 10
  deletion_protection = false

}
