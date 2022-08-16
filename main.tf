provider "aws" {
  region = "ap-south-1"
  profile = "default"
} 


#####Create an application load balancer SG

resource "aws_security_group" "alb" {
  name        = "terraform_alb_security_group"
  description = "Terraform load balancer security group"
  vpc_id      = "${aws_vpc.vpc.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = "${var.allowed_cidr_blocks}"
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = "${var.allowed_cidr_blocks}"
  }
 # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags =  {
    Name = "alb-security-group"
  }
}

resource "aws_alb" "alb" {
  name            = "terraform-example-alb"
  security_groups = ["${aws_security_group.alb.id}"]
  subnets         = ["${aws_subnet.main.id}","${aws_subnet.main1.id}"]
  tags = {
    Name = "Task-alb"
  }
}
##### create new target group

resource "aws_alb_target_group" "group" {
  name     = "terraform-example-alb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.vpc.id}"
  stickiness {
    type = "lb_cookie"
  }
  # Alter the destination of the health check to be the login page.
  health_check {
    path = "/login"
    port = 80
  }
}
resource "aws_alb_target_group_attachment" "group" {
  target_group_arn = "${aws_alb_target_group.group.arn}"
  target_id  = aws_instance.webTier[count.index].id
  count = length(var.webservers)
  port = 80
}
##### CREATE ALB  listerners


resource "aws_alb_listener" "listener_http" {
  load_balancer_arn = "${aws_alb.alb.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.group.arn}"
    type             = "forward"
  }
}
resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone       = var.availability_zones[0]

  tags = {
    Name = "Main"
  }
}
resource "aws_subnet" "main1" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.4.0/24"
  availability_zone       = var.availability_zones[1]

  tags = {
    Name = "Main"
  }
}


##     Launch Instance ###
resource "aws_instance" "webTier" {
  ami = var.ami
  instance_type = var.instance_type
  count = length(var.webservers)
  subnet_id = aws_subnet.public_subnet.id
  tags = {
      Name = var.webservers[count.index]
}
}

resource "aws_db_instance" "p_mydb" {
  allocated_storage = 10
  engine = var.engine
  engine_version = "8.0.28"
  instance_class = var.instance_class
  db_name = "mydb"
  username = var.username
  password = var.password
  skip_final_snapshot = true
 
}
 
# VPC
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Subnets
# Internet Gateway for Public Subnet
resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.vpc.id
  
}

# Elastic-IP (eip) for NAT
resource "aws_eip" "nat_eip" {
  vpc        = true
}

# NAT
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name        = "nat"
  }
}

# Public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
}


# Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = false

}
# Routing tables to route traffic for Private Subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id

  }

# Routing tables to route traffic for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  }

# Route for Internet Gateway
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig.id
}

# Route for NAT
resource "aws_route" "private_nat_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

# Route table associations for both Public & Private Subnets
resource "aws_route_table_association" "public" {
  
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {

  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private.id
}


resource "aws_security_group" "dbsg" {
  name        = "mysqlallow"
  description = "Default SG to alllow traffic from the VPC"
  vpc_id      = "${aws_vpc.vpc.id}"
  depends_on =  [
    aws_vpc.vpc
  ]

    ingress {
    from_port = "22"
    to_port   = "22"
    protocol  = "tcp"
    self      = true
  }
     ingress {
    from_port = "3306"
    to_port   = "3306"
    protocol  = "tcp"
    self      = true
  }
}