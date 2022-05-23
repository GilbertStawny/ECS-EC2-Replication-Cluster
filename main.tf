provider "aws" {
  region = var.region
}

provider "lacework" {}

/* Loads ecs module and creates ECS cluster */

module "ecs" {
  source             = "terraform-aws-modules/ecs/aws"
  version            = "3.4.1"
  name               = var.clusterName
  create_ecs         = true
  container_insights = true
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE_SPOT"
    }
  ]
  tags = {
    temp    = "true"
    creator = var.creator
  }
}

/* Queries for the latest ECS optimized AMI to use for our cluster instances */

data "aws_ami" "latest_ecs_image" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-2*x86_64*"]
  }
}

/* Creates the VPC and public subnet to deploy our new cluster into */

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name    = "${var.clusterName}-vpc"
    creator = var.creator
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.public_subnets_cidr)
  cidr_block              = element(var.public_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = false
  tags = {
    Name    = "${var.clusterName}-${element(var.availability_zones, count.index)}-public-subnet"
    creator = var.creator
  }
}

resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name    = "${var.clusterName}-igw"
    creator = var.creator
  }
}

/* Routing table for public subnet and IGW */
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name    = "${var.clusterName}-public-route-table"
    creator = var.creator
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

/* Creates private subnet and NAT */

resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.private_subnets_cidr)
  cidr_block              = element(var.private_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = false
  tags = {
    Name    = "${var.clusterName}-${element(var.availability_zones, count.index)}-private-subnet"
    creator = var.creator
  }
}

/* Create EIP and NAT for private subnet */

resource "aws_eip" "nat_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.ig]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = element(aws_subnet.public_subnet.*.id, 0)
  depends_on    = [aws_internet_gateway.ig]
  tags = {
    Name    = "${var.clusterName}-nat"
    creator = var.creator
  }
}

/* Create route table for our private subnet and add NAT to it */

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name    = "${var.clusterName}-private-route-table"
    creator = var.creator
  }
}

resource "aws_route" "private_nat_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets_cidr)
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

/* VPC's Default Security Group */
resource "aws_security_group" "default" {
  name        = "${var.clusterName}-default-sg"
  description = "Default security group to allow inbound/outbound from the VPC"
  vpc_id      = aws_vpc.vpc.id
  depends_on  = [aws_vpc.vpc]
  ingress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = "true"
  }
  tags = {
    creator = var.creator
  }
}

/* Create instance role required to join ECS cluster and utilize SSM session manager functionality */

resource "aws_iam_role" "ecs_role" {
  name = "${var.clusterName}-ecs_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "ecs_policy" {
  name = "${var.clusterName}-ecs_policy"
  role = aws_iam_role.ecs_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeTags",
          "ecs:CreateCluster",
          "ecs:DeregisterContainerInstance",
          "ecs:DiscoverPollEndpoint",
          "ecs:Poll",
          "ecs:RegisterContainerInstance",
          "ecs:StartTelemetrySession",
          "ecs:UpdateContainerInstancesState",
          "ecs:Submit*",
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "s3:GetObject",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetEncryptionConfiguration",
          "ssm:DescribeAssociation",
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:GetDocument",
          "ssm:DescribeDocument",
          "ssm:GetManifest",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:PutInventory",
          "ssm:PutComplianceItems",
          "ssm:PutConfigurePackageResult",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "${var.clusterName}_ecs_instance_profile"
  role = aws_iam_role.ecs_role.name
  tags = {
    creator = var.creator
  }
}

/* Create container instance and add it to our ECS cluster */

resource "aws_instance" "containerInstance" {
  ami                  = data.aws_ami.latest_ecs_image.id
  instance_type        = "t2.small"
  user_data            = <<-EOF
  #!/bin/bash
  echo "ECS_CLUSTER=${var.clusterName}" >> /etc/ecs/ecs.config
  echo "ECS_LOGLEVEL=debug" >> /etc/ecs/ecs.config
  EOF
  subnet_id            = element(aws_subnet.private_subnet.*.id, 0)
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name
  tags = {
    Name    = "${var.clusterName}-ClusterInstance"
    creator = var.creator
  }
  monitoring = true
  metadata_options {
    http_endpoint = "disabled"
    http_tokens   = "required"
  }
  ebs_optimized = true
}

module "lacework_ecs_datacollector" {
  source  = "lacework/ecs-agent/aws"
  version = "~> 0.1"

  ecs_cluster_arn       = "arn:aws:ecs:${var.region}:${var.account_id}:cluster/${var.clusterName}"
  lacework_access_token = var.lw_token
  lacework_server_url   = var.lw_url
}


