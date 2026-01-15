# Your existing code remains unchanged...
# ...

# Second task definition for the "Green" environment
resource "aws_ecs_task_definition" "container_task_definition_green" {
  # (Similar to your existing blue task definition but possibly with a different container image)
  # ...
}

# Second ECS service for the "Green" environment
resource "aws_ecs_service" "container_service_green" {
  name            = "container_service_green"
  cluster         = aws_ecs_cluster.container_cluster.id
  task_definition = aws_ecs_task_definition.container_task_definition_green.arn
  desired_count   = 1
  launch_type     = "FARGATE"

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
    target_group_arn = aws_lb_target_group.ecs_target_group_green.arn
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# Listener to switch between Blue and Green target groups
resource "aws_lb_listener" "ecs_lb_listener_http_80" {
  load_balancer_arn = aws_lb.ecs_load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    # Toggle between aws_lb_target_group.ecs_target_group_blue.arn and aws_lb_target_group.ecs_target_group_green.arn
    # to perform Blue/Green deployments
    target_group_arn = aws_lb_target_group.ecs_target_group_blue.arn 
  }
}

# ... Your existing code for scaling, alarms, etc., remains unchanged
# ...

