# Production-Ready Multi-VM Inferencing Mesh Deployment

This guide outlines the deployment of the distributed language model inferencing mesh across isolated AWS subnets using **Docker**, **Nginx**, and **Terraform IaC**.

---

## Architecture Topology

The network design prioritizes network hygiene, ensuring that internal services remain fully hidden in private subnets, while only the API gateway VM is reachable from the public internet.

```
                  +--------------------------------------------------------------------------------+
                  |                                  AWS VPC                                       |
                  |                                                                                |
                  |  +-------------------------+            +-----------------------------------+  |
                  |  |      Public Subnet      |            |         Private Subnets           |  |
                  |  |       (10.0.1.0/24)     |            |                                   |  |
                  |  |                         |            |  +-----------------------------+  |  |
                  |  |  +-------------------+  |            |  |  Caller Subnet (10.0.2.0/24) |  |  |
                  |  |  |   Nginx EC2       |  |            |  |                             |  |  |
Public Client ----+---->|   (Port 80)       |--+-- (RPC) --+-->|  TypeScript Caller Worker   |  |  |
  (Internet)      |  |  |   [Public VM]     |  |  (Private) |  |  + iii Coordination Engine  |  |  |
                  |  |  +-------------------+  |            |  |  [Private VM]               |  |  |
                  |  |                         |            |  +-----------------------------+  |  |
                  |  +-------------------------+            |                 |                 |  |
                  |                                         |                 | RPC (WebSocket) |  |
                  |                                         |                 v                 |  |
                  |  +-------------------------+            |  +-----------------------------+  |  |
                  |  |      NAT Gateway        |<-----------+--|  Inference Subnet           |  |  |
                  |  |      (For outbound)     |            |  |  (10.0.3.0/24)              |  |  |
                  |  +-------------------------+            |  |                             |  |  |
                  |              |                          |  |  Python inference-worker    |  |  |
                  |              v                          |  |  (Gemma 3 270m SLM)         |  |  |
                  |         (Internet)                      |  |  [Private VM]               |  |  |
                  |      [HF / Docker Hub]                  |  +-----------------------------+  |  |
                  |                                         +-----------------------------------+  |
                  +--------------------------------------------------------------------------------+
```

### Routing & Network Security Principles:
1. **Public Subnet**: Contains a single `t3.micro` EC2 running **Nginx** acting as a reverse proxy, connected to the outside world via an **Internet Gateway**.
2. **Private Subnets**: Contain the core processing nodes (`caller-worker` and `inference-worker`). They do **not** have public IPs. All ingress is blocked except for required RPC ports from specific internal security groups.
3. **Outbound Access**: The private subnets route outbound traffic (`0.0.0.0/0`) through a **NAT Gateway** located in the public subnet. This allows `inference-worker` to safely pull model weights from the Hugging Face Hub, and allows both instances to pull Docker images from Docker Hub.

---

## Part 1: Build and Push Docker Images

Before deploying the infrastructure, build your local source directories into production-grade Docker images.

Replace `yourdockerhubusername` with your real Docker Hub registry ID. For this repo, the caller image should be pushed as `cultivator404/caller-worker:latest`:

### 1. Build and Push the `caller-worker` image
```bash
cd ../workers/caller-worker
docker build -t yourdockerhubusername/caller-worker:latest .
docker push yourdockerhubusername/caller-worker:latest
```

### 2. Build and Push the `inference-worker` image
```bash
cd ../inference-worker
docker build -t yourdockerhubusername/inference-worker:latest .
docker push yourdockerhubusername/inference-worker:latest
```

### 3. Build and Push the `nginx-gateway` image
```bash
cd ../../nginx
docker build -t yourdockerhubusername/nginx-gateway:latest .
docker push yourdockerhubusername/nginx-gateway:latest
```

---

## Part 2: Provision Infrastructure using Terraform

Once your images are available on Docker Hub, Terraform will deploy the networks and automatically bootstrap the virtual machines to install Docker and start the containers.

### 1. Configure Credentials and Variables
Initialize your AWS environment. If you want to customize values (such as region, Docker Hub username, or SSH keys), create a `terraform.tfvars` file:

```hcl
aws_region       = "us-east-1"
docker_username  = "cultivator404"
docker_image_tag = "latest"
key_name         = "my-aws-ssh-key"
```

### 2. Launch the Stack
Initialize Terraform, review the resource plans, and apply the provisioning rules:

```bash
terraform init
terraform plan
terraform apply
```

Terraform outputs the Nginx public IP and a pre-configured `curl` command upon completion.

---

## Part 3: Test and Verify the API

Once Terraform completes, it may take 1 to 2 minutes for the instances to finish installing Docker, pulling the images, and caching the model weights from Hugging Face.

You can verify the API is operational using the curl command provided in the Terraform outputs:

```bash
# Example Verification Command
curl -X POST http://<NGINX_PUBLIC_IP>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "Explain quantum computing in one short sentence."}
    ]
  }'
```

### Sample JSON Response:
```json
{
  "result": "Quantum computing uses subatomic physics to process complex data infinitely faster than classical computers.",
  "success": "You've connected two workers and they're interoperating seamlessly, now let's add a few more workers to expand this project's functionality."
}
```

---

## Part 4: Production Hardening & Scaling (100x Model Size)

### A. What to Harden Before Going to Production
1. **Secrets Management**: Remove all hardcoded references or manual configurations. Store secrets (e.g. AWS keys, Hugging Face auth tokens) securely in AWS Secrets Manager or Systems Manager Parameter Store.
2. **Access Control (Least Privilege)**: Remove global SSH rules (`0.0.0.0/22`). Restrict SSH accesses via AWS Systems Manager Session Manager (SSM) which eliminates the need to expose open ports or use bastion hosts entirely.
3. **Transport Security (HTTPS)**: Enable SSL/TLS certificates on Nginx using AWS Certificate Manager (ACM) mapped to a Route 53 DNS domain.
4. **Resiliency & Auto Scaling**: Migrate the single gateway to an Application Load Balancer (ALB) targeting an Auto Scaling Group (ASG) of worker nodes.
5. **Observability**: Direct logs and spans to AWS CloudWatch or a hosted Grafana/Jaeger agent for distributed span analysis.

### B. Scalability for Models 100x Larger (e.g., 27B+ parameters)
If we were to scale from a tiny `270M` parameter model to a `27B` model, the model would no longer fit inside cheap, generic CPU memory tiers:
1. **GPU Accelerators**: Shift the `inference-worker` tier onto accelerated instance types (e.g. AWS `g5` or `p4` instances running NVIDIA A10G/A100 GPUs) to meet prompt-completion latency SLAs.
2. **Model Parallelism & Distributed Inference**: Leverage frameworks like **vLLM**, **TGI (Text Generation Inference)**, or **DeepSpeed** to split model layers across tensor-parallel and pipeline-parallel GPUs.
3. **Dynamic Batching & Inference Queues**: Set up an active queuing system (like `iii-queue`backed by Redis/SQS) to process incoming traffic streams concurrently, batching prompt inferences to maximize GPU hardware utilization.
4. **Caching Tier**: Place a high-performance Redis/ElastiCache cluster in front of the caller to run semantic prompt caching, avoiding expensive model evaluations for duplicate or highly similar queries.
