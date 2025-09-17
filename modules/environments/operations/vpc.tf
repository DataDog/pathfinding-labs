resource "aws_vpc" "pathfinder" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  instance_tenancy     = "default"
  tags = {
    Name = "pathfinder"
  } 
}

resource "aws_internet_gateway" "pathfinderigw" {
  vpc_id = aws_vpc.pathfinder.id
  tags = {
    Name = "pathfinder Internet Gateway"
  }
}

resource "aws_route_table" "pathfinderpublic" {
  vpc_id = aws_vpc.pathfinder.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pathfinderigw.id
  }
  tags = {
    Name = "pathfinder Public Route Table"
  }
}

resource "aws_subnet" "pathfinderoperational-1" {
  vpc_id                  = aws_vpc.pathfinder.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = var.AWS_REGION_SUB_1
  tags = {
    Name = "pathfinder Operational Subnet 1"
  }
}

resource "aws_subnet" "pathfinderoperational-2" {
  vpc_id                  = aws_vpc.pathfinder.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = var.AWS_REGION_SUB_2
  tags = {
    Name = "pathfinder Operational Subnet 2"
  }
}

resource "aws_subnet" "pathfinderoperational-3" {
  vpc_id                  = aws_vpc.pathfinder.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = var.AWS_REGION_SUB_3
  tags = {
    Name = "pathfinder Operational Subnet 3"
  }
}

resource "aws_route_table_association" "pathfinderoperational-1" {
  subnet_id      = aws_subnet.pathfinderoperational-1.id
  route_table_id = aws_route_table.pathfinderpublic.id
}

resource "aws_route_table_association" "pathfinderoperational-2" {
  subnet_id      = aws_subnet.pathfinderoperational-2.id
  route_table_id = aws_route_table.pathfinderpublic.id
}

resource "aws_route_table_association" "pathfinderoperational-3" {
  subnet_id      = aws_subnet.pathfinderoperational-3.id
  route_table_id = aws_route_table.pathfinderpublic.id
}




// output vpc_id
output "vpc_id" {
  value = aws_vpc.pathfinder.id
}

output "vpc_cidr" {
  value = aws_vpc.pathfinder.cidr_block
}

// output subnet_id
output "subnet1_id" {
  value = aws_subnet.pathfinderoperational-1.id
}

output "subnet2_id" {
  value = aws_subnet.pathfinderoperational-2.id
}

output "subnet3_id" {
  value = aws_subnet.pathfinderoperational-3.id
}