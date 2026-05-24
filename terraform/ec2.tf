# Upload the local public SSH key to AWS Key Pairs
resource "aws_key_pair" "deployer" {
  key_name   = "llm-mesh-deployer-key"
  public_key = file("${path.module}/../terraform-key.pub")
}

# Data source for latest Ubuntu 22.04 LTS
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical owner ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 1. Caller Instance (Private Subnet 1): Coordinates iii engine and runs TypeScript caller worker
resource "aws_instance" "caller" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_caller
  subnet_id              = aws_subnet.private_caller.id
  vpc_security_group_ids = [aws_security_group.caller.id]
  key_name               = aws_key_pair.deployer.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 16
  }

  user_data = <<-EOF
              #!/bin/bash
              # Configure 3GB Swapfile to prevent OOM on t3.micro
              fallocate -l 3G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # Update and Install Docker
              apt-get update -y
              apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
              mkdir -p /etc/apt/keyrings
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
              echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
              apt-get update -y
              apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
              systemctl enable docker
              systemctl start docker

              # Create directories for iii engine
              mkdir -p /app/data
              
              # Write engine configuration file
              cat <<'INNER_EOF' > /app/iii-engine-config.yaml
              workers:
                - name: iii-observability
                  config:
                    enabled: true
                    service_name: iii
                    exporter: memory
                    memory_max_spans: 10000
                    metrics_enabled: true
                    metrics_exporter: memory
                    logs_enabled: true
                    logs_exporter: memory
                    logs_console_output: true
                    sampling_ratio: 1.0
                - name: iii-queue
                  config:
                    adapter:
                      name: builtin
                - name: iii-state
                  config:
                    adapter:
                      name: kv
                      config:
                        store_method: file_based
                        file_path: /app/data/state_store.db
                - name: iii-http
                  config:
                    port: 3111
                    host: 0.0.0.0
                    default_timeout: 300000
                    concurrency_request_limit: 1024
                    cors:
                      allowed_origins:
                      - '*'
                      allowed_methods:
                      - GET
                      - POST
                      - PUT
                      - DELETE
                      - OPTIONS
              INNER_EOF

              # Start central iii engine container
              docker run -d --name iii-engine \
                --restart always \
                -p 3111:3111 \
                -p 49134:49134 \
                -v /app/data:/app/data \
                -v /app/iii-engine-config.yaml:/app/config.yaml:ro \
                iiidev/iii:latest

              # Give the engine a brief moment to start
              sleep 5

              # Pull and run caller worker container pointing to the engine
              docker pull ${var.docker_username}/caller-worker:${var.docker_image_tag}
              docker run -d --name caller-worker \
                --restart always \
                --network host \
                -e III_URL=ws://127.0.0.1:49134 \
                ${var.docker_username}/caller-worker:${var.docker_image_tag}

              # Wait until the iii HTTP port is reachable before exposing it through Nginx
              for i in $(seq 1 60); do
                if timeout 1 bash -c '</dev/tcp/127.0.0.1/3111' >/dev/null 2>&1; then
                  break
                fi
                sleep 5
              done

              # Start Watchtower to auto-update containers when new images are pushed
              docker run -d --name watchtower \
                --restart always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                containrrr/watchtower --cleanup --interval 300
              EOF

  tags = {
    Name = "llm-caller-instance"
  }
}

# 2. Inference Instance (Private Subnet 2): Pulls inference worker and processes Gemma queries
resource "aws_instance" "inference" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_inference
  subnet_id              = aws_subnet.private_inference.id
  vpc_security_group_ids = [aws_security_group.inference.id]
  key_name               = aws_key_pair.deployer.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 16
  }

  user_data = <<-EOF
              #!/bin/bash
              # Configure 3GB Swapfile to prevent OOM on t3.micro
              fallocate -l 3G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # Update and Install Docker
              apt-get update -y
              apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
              mkdir -p /etc/apt/keyrings
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
              echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
              apt-get update -y
              apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
              systemctl enable docker
              systemctl start docker

              # Pull and run Python inference worker container pointing to Caller IP RPC port
              docker pull ${var.docker_username}/inference-worker:${var.docker_image_tag}
              docker run -d --name inference-worker \
                --restart always \
                -e III_URL=ws://${aws_instance.caller.private_ip}:49134 \
                ${var.docker_username}/inference-worker:${var.docker_image_tag}

              # Start Watchtower to auto-update containers when new images are pushed
              docker run -d --name watchtower \
                --restart always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                containrrr/watchtower --cleanup --interval 300
              EOF

  tags = {
    Name = "llm-inference-instance"
  }

  depends_on = [aws_instance.caller]
}

# 3. Nginx Gateway Instance (Public Subnet): Reverse proxy for internet-facing inference trigger
resource "aws_instance" "nginx" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_nginx
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.nginx.id]
  key_name               = aws_key_pair.deployer.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
  }

  user_data = <<-EOF
              #!/bin/bash
              # Update and Install Docker
              apt-get update -y
              apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
              mkdir -p /etc/apt/keyrings
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
              echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
              apt-get update -y
              apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
              systemctl enable docker
              systemctl start docker

              # Wait for the caller instance HTTP port before starting Nginx
              for i in $(seq 1 60); do
                if timeout 1 bash -c '</dev/tcp/${aws_instance.caller.private_ip}/3111' >/dev/null 2>&1; then
                  break
                fi
                sleep 5
              done
              
              # Pull and run nginx gateway container built from repo image (if used)
              # If an image is pushed to the registry, Watchtower will update it automatically.
              # Start Watchtower to auto-update containers when new images are pushed
              docker run -d --name watchtower \
                --restart always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                containrrr/watchtower --cleanup --interval 300

              # Pull and run custom Nginx container with dynamic caller worker private IP
              docker pull ${var.docker_username}/nginx-serve:${var.docker_image_tag}
              docker run -d --name nginx-gateway \
                --restart always \
                -p 80:80 \
                -e CALLER_IP=${aws_instance.caller.private_ip} \
                ${var.docker_username}/nginx-serve:${var.docker_image_tag}
              EOF

  tags = {
    Name = "llm-nginx-gateway-instance"
  }

  depends_on = [aws_instance.caller]
}

# 4. NAT Instance (Public Subnet): Provides Free-Tier NAT gateway services for private instances
resource "aws_instance" "nat" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.nat.id]
  source_dest_check      = false
  key_name               = aws_key_pair.deployer.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
  }

  user_data = <<-EOF
              #!/bin/bash
              # Enable IP forwarding
              sysctl -w net.ipv4.ip_forward=1
              echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
              
              # Dynamically detect primary network interface
              PRIMARY_IF=$(ip route | grep default | awk '{print $5}')
              
              # Configure IPTables NAT masquerading using the correct interface
              iptables -t nat -A POSTROUTING -o $PRIMARY_IF -j MASQUERADE
              
              # Install iptables-persistent non-interactively to prevent hanging on prompts
              export DEBIAN_FRONTEND=noninteractive
              echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
              echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
              apt-get update -y
              apt-get install -y iptables-persistent
              netfilter-persistent save
              EOF

  tags = {
    Name = "llm-nat-instance"
  }
}
