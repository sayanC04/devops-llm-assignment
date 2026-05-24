variable "aws_region" {
  type        = string
  description = "AWS region to deploy the infrastructure"
  default     = "us-east-1"
}

variable "instance_type_nginx" {
  type        = string
  description = "EC2 Instance type for the public Nginx gateway"
  default     = "t3.micro"
}

variable "instance_type_caller" {
  type        = string
  description = "EC2 Instance type for the TypeScript caller-worker & iii engine"
  default     = "t3.micro"
}

variable "instance_type_inference" {
  type        = string
  description = "EC2 Instance type for the Python inference-worker (needs RAM for LLM)"
  default     = "t3.medium"
}

variable "key_name" {
  type        = string
  description = "Name of the SSH Key Pair to enable access to the EC2 instances (optional)"
  default     = null
}

variable "docker_username" {
  type        = string
  description = "Docker Hub username where images are hosted"
  default     = "cultivator404"
}

variable "docker_image_tag" {
  type        = string
  description = "Tag of the Docker images to deploy"
  default     = "latest"
}
