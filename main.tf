# Provider Configuration
provider "aws" {
  region = "us-west-2"
}

# VPC Creation
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Public Subnet Creation
resource "aws_subnet" "public" {
  count = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index)
  map_public_ip_on_launch = true
  availability_zone       = ["us-west-2a", "us-west-2b"][count.index]
}

# Private Subnet Creation
resource "aws_subnet" "private" {
  count = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 4, 2 + count.index)
  availability_zone = ["us-west-2a", "us-west-2b"][count.index]
}

# Internet Gateway Creation
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

# Route Table Association for Public Subnet
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Group for Public Subnet
resource "aws_security_group" "ajay_public_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for Private Subnet
resource "aws_security_group" "ajay_private_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.ajay_public_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch Template for Public EC2 Instances
resource "aws_launch_template" "ajay_public_instance" {
  name          = "ajay-public-instance-template"
  instance_type = "t2.micro"
  image_id      = "ami-055e3d4f0bbeb5878" 
  iam_instance_profile {
    name = aws_iam_instance_profile.ajay_public_role.name
  }
  vpc_security_group_ids = [aws_security_group.ajay_public_sg.id]
}

# Auto Scaling Group for Public EC2 Instances
resource "aws_autoscaling_group" "ajay_public_asg" {
  desired_capacity    = 2
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = [
    aws_subnet.public[0].id,
    aws_subnet.public[1].id
  ]
  launch_template {
    id      = aws_launch_template.ajay_public_instance.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.ajay_app_targets.arn]
}

# Private EC2 Instance
resource "aws_instance" "ajay_private_instance" {
  ami                    = "ami-055e3d4f0bbeb5878"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.ajay_private_sg.id]
}

# Application Load Balancer
resource "aws_lb" "ajay_application_lb" {
  name               = "ajay-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ajay_public_sg.id]
  subnets            = [
    aws_subnet.public[0].id,
    aws_subnet.public[1].id
  ]
}

# Target Group for Application Load Balancer
resource "aws_lb_target_group" "ajay_app_targets" {
  name     = "ajay-app-targets"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

# Listener for Application Load Balancer
resource "aws_lb_listener" "ajay_app_listener" {
  load_balancer_arn = aws_lb.ajay_application_lb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ajay_app_targets.arn
  }
}

# Network Load Balancer
resource "aws_lb" "ajay_network_lb" {
  name               = "ajay-net-lb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [
    aws_subnet.private[0].id,
    aws_subnet.private[1].id
  ]
}

# Target Group for Network Load Balancer
resource "aws_lb_target_group" "ajay_network_targets" {
  name     = "ajay-net-targets"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id
}

# Listener for Network Load Balancer
resource "aws_lb_listener" "ajay_net_listener" {
  load_balancer_arn = aws_lb.ajay_network_lb.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ajay_network_targets.arn
  }
}

# S3 Bucket
resource "aws_s3_bucket" "ajay_private_bucket" {
  bucket = "ajay-private-bucket"
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "ajay_private_bucket_versioning" {
  bucket = aws_s3_bucket.ajay_private_bucket.bucket

  versioning_configuration {
    status = "Enabled"
  }
}

# IAM Role
resource "aws_iam_role" "ajay_public_role" {
  name               = "ajay-public-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

# IAM Policy for S3 Access
resource "aws_iam_policy" "ajay_s3_access" {
  name        = "ajay-s3-access-unique"
  description = "Full access to the S3 bucket"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["s3:*"],
        Effect   = "Allow",
        Resource = [aws_s3_bucket.ajay_private_bucket.arn, "${aws_s3_bucket.ajay_private_bucket.arn}/*"]
      }
    ]
  })
}

# Attach IAM Policy to Role
resource "aws_iam_role_policy_attachment" "ajay_attach_policy" {
  role       = aws_iam_role.ajay_public_role.name
  policy_arn = aws_iam_policy.ajay_s3_access.arn
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ajay_public_role" {
  name = "ajay-public-instance-profile-unique"
  role = aws_iam_role.ajay_public_role.name
}
