resource "aws_vpc" "pathfinding" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  instance_tenancy     = "default"
  tags = {
    Name = "pathfinding"
  }
}

resource "aws_internet_gateway" "pathfindingigw" {
  vpc_id = aws_vpc.pathfinding.id
  tags = {
    Name = "pathfinding Internet Gateway"
  }
}

resource "aws_route_table" "pathfindingpublic" {
  vpc_id = aws_vpc.pathfinding.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pathfindingigw.id
  }
  tags = {
    Name = "pathfinding Public Route Table"
  }
}

resource "aws_subnet" "pathfindingoperational-1" {
  vpc_id                  = aws_vpc.pathfinding.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = var.AWS_REGION_SUB_1
  tags = {
    Name = "pathfinding Operational Subnet 1"
  }
}

resource "aws_subnet" "pathfindingoperational-2" {
  vpc_id                  = aws_vpc.pathfinding.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = var.AWS_REGION_SUB_2
  tags = {
    Name = "pathfinding Operational Subnet 2"
  }
}

resource "aws_subnet" "pathfindingoperational-3" {
  vpc_id                  = aws_vpc.pathfinding.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = var.AWS_REGION_SUB_3
  tags = {
    Name = "pathfinding Operational Subnet 3"
  }
}

resource "aws_route_table_association" "pathfindingoperational-1" {
  subnet_id      = aws_subnet.pathfindingoperational-1.id
  route_table_id = aws_route_table.pathfindingpublic.id
}

resource "aws_route_table_association" "pathfindingoperational-2" {
  subnet_id      = aws_subnet.pathfindingoperational-2.id
  route_table_id = aws_route_table.pathfindingpublic.id
}

resource "aws_route_table_association" "pathfindingoperational-3" {
  subnet_id      = aws_subnet.pathfindingoperational-3.id
  route_table_id = aws_route_table.pathfindingpublic.id
}




// output vpc_id
output "vpc_id" {
  value = aws_vpc.pathfinding.id
}

output "vpc_cidr" {
  value = aws_vpc.pathfinding.cidr_block
}

// output subnet_id
output "subnet1_id" {
  value = aws_subnet.pathfindingoperational-1.id
}

output "subnet2_id" {
  value = aws_subnet.pathfindingoperational-2.id
}

output "subnet3_id" {
  value = aws_subnet.pathfindingoperational-3.id
}