# Provider Configuration
provider "aws" {
  region = "us-west-2"
}

# VPC and Subnets
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  count = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index)
  map_public_ip_on_launch = true
  availability_zone       = ["us-west-2a", "us-west-2b"][count.index]
}

resource "aws_subnet" "private" {
  count = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 4, 2 + count.index)
  availability_zone = ["us-west-2a", "us-west-2b"][count.index]
}

# Internet Gateway
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

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "srihari_public_sg" {
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

resource "aws_security_group" "srihari_private_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.srihari_public_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instances and ASG
resource "aws_launch_template" "srihari_public_instance" {
  name          = "srihari-public-instance-template"
  instance_type = "t2.micro"
  image_id      = "ami-055e3d4f0bbeb5878" # Amazon Linux 2 AMI
  iam_instance_profile {
    name = aws_iam_instance_profile.srihari_public_role.name
  }
  vpc_security_group_ids = [aws_security_group.srihari_public_sg.id]
}

resource "aws_autoscaling_group" "srihari_public_asg" {
  desired_capacity    = 2
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = aws_subnet.public[*].id
  launch_template {
    id      = aws_launch_template.srihari_public_instance.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.srihari_app_targets.arn]
}

resource "aws_instance" "srihari_private_instance" {
  ami                    = "ami-055e3d4f0bbeb5878"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.srihari_private_sg.id]
}

# Load Balancers
resource "aws_lb" "srihari_application" {
  name               = "srihari-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.srihari_public_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "srihari_app_targets" {
  name     = "srihari-app-targets"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "srihari_app_listener" {
  load_balancer_arn = aws_lb.srihari_application.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.srihari_app_targets.arn
  }
}

resource "aws_lb" "srihari_network" {
  name               = "srihari-net-lb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id
}

resource "aws_lb_target_group" "srihari_network_targets" {
  name     = "srihari-net-targets"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id
}

# S3 Bucket
resource "aws_s3_bucket" "srihari_private_bucket" {
  bucket = "srihari-private-bucket"
  acl    = "private"
  versioning {
    enabled = true
  }
}

# IAM Role
resource "aws_iam_role" "srihari_public_role" {
  name               = "srihari-public-role"
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

resource "aws_iam_policy" "srihari_s3_access" {
  name        = "srihari-s3-access"
  description = "Full access to the S3 bucket"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["s3:*"],
        Effect   = "Allow",
        Resource = [aws_s3_bucket.srihari_private_bucket.arn, "${aws_s3_bucket.srihari_private_bucket.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "srihari_attach_policy" {
  role       = aws_iam_role.srihari_public_role.name
  policy_arn = aws_iam_policy.srihari_s3_access.arn
}

resource "aws_iam_instance_profile" "srihari_public_role" {
  name = "srihari-public-instance-profile"
  role = aws_iam_role.srihari_public_role.name
}
