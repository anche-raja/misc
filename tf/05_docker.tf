
# This is where we pull in the latest AMI ID for Amazon Linux 2023
data "aws_ami" "amazon_linux_base_image" {
  most_recent = true
  filter {
    name   = "name"
    values = ["al2023-ami-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
# This is where we create the role to be used by the server for getting to AWS resources
resource "aws_iam_role" "docker_server_role" {
  name = join("-", [var.base_name, "docker_server_role"])
  assume_role_policy = jsonencode({
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  inline_policy {
    name = join("-", [var.base_name, "docker_server_role_ecr_full_access"])
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "FullAccess"
          Action   = "*"
          Effect   = "Allow"
          Resource = "*"
        }
      ]
    })
  }
}

# This is where we create the instance profile
resource "aws_iam_instance_profile" "docker_server_profile" {
  name = join("-", [var.base_name, "docker_server_profile"])
  role = aws_iam_role.docker_server_role.name
}
# This is where we build the EC2 docker server/bastion host, which is used to issue docker commands and has access to talk to all AWS services
resource "aws_instance" "docker_server" {
  ami                         = data.aws_ami.amazon_linux_base_image.id
  iam_instance_profile        = aws_iam_instance_profile.docker_server_profile.name
  instance_type               = "t3.small"
  associate_public_ip_address = true
  key_name                    = var.ec2_key_name
  metadata_options {
    http_tokens = "required"
  }
  subnet_id       = aws_subnet.public_subnet_a.id
  security_groups = [aws_security_group.allow_ssh_and_http_from_workspaces.id]
  user_data       = <<EOF
#!/bin/bash
sudo yum update -y
sudo yum install nano -y
sudo yum install docker -y
sudo dnf -y install mariadb105
sudo yum -y install java-17-amazon-corretto-headless
sudo usermod -a -G docker ec2-user
sudo id ec2-user
sudo newgrp docker
sudo systemctl enable docker.service
sudo systemctl start docker.service
echo 'FROM amazoncorretto:17' > /tmp/Dockerfile
echo 'EXPOSE 80' >> /tmp/Dockerfile
cat /tmp/Dockerfile
aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com
docker build -f /tmp/Dockerfile -t ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/container-repository:latest /tmp
docker images
IMAGE_ID=$(docker images -q ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/container-repository)
echo "Here is the image ID to be pushed:"
echo $IMAGE_ID
docker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/container-repository:latest
echo 'Script complete.  Exiting.'
EOF
}


resource "aws_iam_role_policy_attachment" "attachment_to_dockerserver_role" {
  role       = aws_iam_role.docker_server_role.name
  policy_arn = aws_iam_policy.rds_auth_policy.arn
}