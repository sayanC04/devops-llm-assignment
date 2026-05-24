# Security Group for Public Nginx reverse proxy
resource "aws_security_group" "nginx" {
  name        = "nginx-gateway-sg"
  description = "Allow public HTTP traffic to Nginx"
  vpc_id      = aws_vpc.main.id

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
    cidr_blocks = ["0.0.0.0/0"] # Can be restricted to specific developer IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "llm-nginx-sg"
  }
}

# Security Group for Caller Worker & iii Engine
resource "aws_security_group" "caller" {
  name        = "caller-worker-sg"
  description = "Control traffic to Caller worker and iii engine"
  vpc_id      = aws_vpc.main.id

  # Allow HTTP Gateway traffic (3111) only from Nginx gateway
  ingress {
    from_port       = 3111
    to_port         = 3111
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  # Allow WebSocket RPC traffic (49134) from local self
  ingress {
    from_port = 49134
    to_port   = 49134
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    cidr_blocks = ["10.0.3.0/24"] # Allow connection from private subnet of inference worker
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"] # Allow SSH from public subnet (jump host model)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "llm-caller-sg"
  }
}

# Security Group for Inference Worker
resource "aws_security_group" "inference" {
  name        = "inference-worker-sg"
  description = "Control traffic to ML Inference worker"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"] # Allow SSH from public subnet
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Egress needed to connect to Caller (49134) and fetch models from HuggingFace
  }

  tags = {
    Name = "llm-inference-sg"
  }
}

# Security Group for Free-Tier NAT Instance
resource "aws_security_group" "nat" {
  name        = "nat-instance-sg"
  description = "Allow inbound private subnet traffic for NAT translation"
  vpc_id      = aws_vpc.main.id

  # Allow all inbound traffic from within the VPC CIDR (10.0.0.0/16)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "llm-nat-sg"
  }
}
