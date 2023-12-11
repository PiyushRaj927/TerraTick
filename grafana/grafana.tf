terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.17.0"
    }
  }

  required_version = "~> 1.2"
}

provider "aws" {
  region = "us-east-1"
}

locals {
  project_name = "TerraTick"
  container_name = "terratick-grafana"
  container_port = 3000
  azs = slice(data.aws_availability_zones.available_zones.names, 0, 2)
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
   public_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]
}

# create vpc
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = true

  tags = {
    Name = "${local.project_name}-vpc"
  }
}
resource "aws_internet_gateway" "demogateway" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table" "rt" {
    vpc_id = aws_vpc.vpc.id
	route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.demogateway.id
    }
	tags = {
        Name = "Public Subnet Route Table"
    }

}
resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-a-gw.id
  }

  depends_on = [
    aws_vpc.vpc,
  ]
  tags = {
    Name        = "private-route-table"
  }
}
resource "aws_route_table_association" "rt_associate_public" {
	 count             = length(local.public_subnet_cidrs)
    subnet_id = aws_subnet.public_subnets[count.index].id
    route_table_id = aws_route_table.rt.id
}
resource "aws_route_table_association" "rt_associate_private" {
	 count             = length(local.private_subnet_cidrs)
    subnet_id = aws_subnet.private_subnets[count.index].id
    route_table_id = aws_route_table.private-route-table.id
}


# Nat Gateway

resource "aws_eip" "nat-a-eip" {
  domain               = "vpc"

  depends_on = [
    resource.aws_internet_gateway.demogateway
  ]
}

resource "aws_nat_gateway" "nat-a-gw" {
  	allocation_id = resource.aws_eip.nat-a-eip.id
	subnet_id = resource.aws_subnet.public_subnets[0].id

  tags = {
    Name = "nat gateway A"
  }
}


resource "aws_security_group" "demosg" {
	vpc_id      = "${aws_vpc.vpc.id}" # Inbound Rules
  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }# HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }# SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }# Outbound Rules
  # Internet access to anywhere
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# # use data source to get all avalablility zones in region
data "aws_availability_zones" "available_zones" {}

resource "aws_subnet" "public_subnets" {

 count             = length(local.public_subnet_cidrs)

 vpc_id            = aws_vpc.vpc.id

 cidr_block        = element(local.public_subnet_cidrs, count.index)

 availability_zone = element(local.azs, count.index)
  map_public_ip_on_launch = "true"
 

 tags = {

   Name = "Public Subnet ${count.index + 1}"

 }

}

 

resource "aws_subnet" "private_subnets" {

 count             = length(local.private_subnet_cidrs)

 vpc_id            = aws_vpc.vpc.id

 cidr_block        = element(local.private_subnet_cidrs, count.index)

 availability_zone = element(local.azs, count.index)

 

 tags = {

   Name = "Private Subnet ${count.index + 1}"

 }

}

# resource "aws_security_group" "https" {
# 	description = "Permit incoming HTTPS traffic"
# 	name = "https"
# 	vpc_id = resource.aws_vpc.this.id

# 	ingress {
# 		cidr_blocks = ["0.0.0.0/0"]
# 		from_port = 443
# 		protocol = "TCP"
# 		to_port = 443
# 	}
# }
resource "aws_security_group" "http" {
	description = "Permit incoming HTTP traffic"
	name = "http"
	vpc_id = resource.aws_vpc.vpc.id

	ingress {
		cidr_blocks = ["0.0.0.0/0"]
		from_port = 80
		protocol = "TCP"
		to_port = 80
	}
}
resource "aws_security_group" "egress_all" {
	description = "Permit all outgoing traffic"
	name = "egress-all"
	vpc_id = resource.aws_vpc.vpc.id

	egress {
		cidr_blocks = ["0.0.0.0/0"]
		from_port = 0
		protocol = "-1"
		to_port = 0
	}
}
resource "aws_security_group" "ingress_api" {
	description = "Permit some incoming traffic"
	name = "ingress-esc-service"
	vpc_id = resource.aws_vpc.vpc.id

	ingress {
		cidr_blocks = ["0.0.0.0/0"]
		from_port = local.container_port
		protocol = "TCP"
		to_port = local.container_port
	}
}

resource "aws_lb" "this" {
	load_balancer_type = "application"

	# depends_on = [resource.aws_internet_gateway.this]

	security_groups = [
		resource.aws_security_group.egress_all.id,
		resource.aws_security_group.http.id,
	]

	subnets = resource.aws_subnet.public_subnets[*].id
}
resource "aws_lb_target_group" "this" {
	port = local.container_port
	protocol = "HTTP"
	target_type = "ip"
	vpc_id = resource.aws_vpc.vpc.id

	depends_on = [resource.aws_lb.this]
}

resource "aws_lb_listener" "this" {
	load_balancer_arn = resource.aws_lb.this.arn
	port = 80
	protocol = "HTTP"

	default_action {
		target_group_arn = aws_lb_target_group.this.arn
		type = "forward"
	}
}

resource "aws_ecs_cluster" "grafana_cluster" { name = "${local.project_name}-cluster" } # TODO add a variable for projec name

resource "aws_ecs_cluster_capacity_providers" "terratick_capacity" {
	capacity_providers = ["FARGATE"]
	cluster_name = resource.aws_ecs_cluster.grafana_cluster.name
  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

data "aws_iam_policy_document" "this" {
	version = "2012-10-17"

	statement {
		actions = ["sts:AssumeRole"]
		effect = "Allow"

		principals {
			identifiers = ["ecs-tasks.amazonaws.com"]
			type = "Service"
		}
	}
}
resource "aws_iam_role" "this" { assume_role_policy = data.aws_iam_policy_document.this.json }

resource "aws_iam_role_policy_attachment" "default" {
	policy_arn  = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
	role = resource.aws_iam_role.this.name
}

resource "aws_iam_role_policy_attachment" "default1" {
	policy_arn  = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
	role = resource.aws_iam_role.this.name
}


resource "aws_ecs_task_definition" "grafana_task" {
	container_definitions = jsonencode([{
		essential = true,
		image = "grafana/grafana",
		name = local.container_name,
		portMappings = [{ containerPort = local.container_port }],
		logConfiguration = {
			logDriver = "awslogs"
			options = {
				awslogs-region: "us-east-1",
				 	awslogs-create-group: "true",
                    awslogs-group: "awslogs-wordpress",
                    awslogs-stream-prefix: "terratick-example"
			}
		}
	}])
	cpu = 256
	execution_role_arn = resource.aws_iam_role.this.arn
	family = "family-of-Terratick-tasks"
	memory = 512
	network_mode = "awsvpc"
	requires_compatibilities = ["FARGATE"]
}


resource "aws_ecs_service" "terratick_service" {
	cluster = resource.aws_ecs_cluster.grafana_cluster.id
	desired_count = 1
	launch_type = "FARGATE"
	name = "Terratick-service"
	task_definition = resource.aws_ecs_task_definition.grafana_task.arn
# todo add 'depends_on' as per docs
	lifecycle {
		ignore_changes = [desired_count] # Allow external changes to happen without Terraform conflicts, particularly around auto-scaling.
	}

	load_balancer {
		container_name = local.container_name
		container_port = local.container_port
		target_group_arn = resource.aws_lb_target_group.this.arn
	}

	network_configuration {
		security_groups = [
			resource.aws_security_group.egress_all.id,
			resource.aws_security_group.ingress_api.id,
		]
		subnets =  resource.aws_subnet.private_subnets[*].id
	}
}

