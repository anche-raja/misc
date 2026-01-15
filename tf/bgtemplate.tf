variable "image_tag" {
  default = "latest"
}

variable "active_target_group" {
  default = "blue" # or "green"
}

resource "aws_ecs_cluster" "container_cluster" {
  name = "container_cluster"
}

resource "aws_ecs_task_definition" "container_task_definition" {
  family                   = "container_task_family"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "my-container"
    image = "my-repo:${var.image_tag}"
    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
  }])
}

resource "aws_lb" "alb" {
  # ALB configuration here
}

resource "aws_lb_target_group" "blue_group" {
  # Blue target group configuration
  name = "blue-group"
}

resource "aws_lb_target_group" "green_group" {
  # Green target group configuration
  name = "green-group"
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"

  default_action {
    type             = "forward"
    target_group_arn = var.active_target_group == "blue" ? aws_lb_target_group.blue_group.arn : aws_lb_target_group.green_group.arn
  }
}

resource "aws_ecs_service" "container_service" {
  depends_on      = [aws_nat_gateway.nat_gateway] # (Assuming you have defined aws_nat_gateway resource)
  name            = "container_service"
  cluster         = aws_ecs_cluster.container_cluster.id
  task_definition = aws_ecs_task_definition.container_task_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  
  network_configuration {
    subnets = ["subnet-xxxxxx", "subnet-yyyyyy"]
  }

  load_balancer {
    target_group_arn = var.active_target_group == "blue" ? aws_lb_target_group.blue_group.arn : aws_lb_target_group.green_group.arn
    container_name   = "my-container"
    container_port   = 80
  }

  deployment_controller {
    type = "EXTERNAL"
  }
}
