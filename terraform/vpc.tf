# Create Virtual Private Cloud
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "llm-inferencing-vpc"
  }
}

# Internet Gateway for Public Internet Access
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "llm-inferencing-igw"
  }
}

# Public Subnet (Nginx Gateway)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "llm-public-subnet"
  }
}

# Private Subnet 1 (TypeScript Caller Worker & iii Engine)
resource "aws_subnet" "private_caller" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "llm-private-caller-subnet"
  }
}

# Private Subnet 2 (Python ML Inference Worker)
resource "aws_subnet" "private_inference" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "llm-private-inference-subnet"
  }
}

# Route Table for Public Subnet (To Internet Gateway)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "llm-public-rt"
  }
}

# Route Table for Private Subnets (Routed through the NAT Instance)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat.primary_network_interface_id
  }

  tags = {
    Name = "llm-private-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_caller" {
  subnet_id      = aws_subnet.private_caller.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_inference" {
  subnet_id      = aws_subnet.private_inference.id
  route_table_id = aws_route_table.private.id
}
