# Distributed Inferencing Prototype

A prototype that runs a small language model behind a distributed worker mesh. A Python worker hosts the model and exposes inference as an RPC function; a TypeScript worker fans incoming HTTP requests into that RPC and returns the result as JSON. The two workers are written in different languages, can run on different machines, and are composed at runtime — so you can scale the inference tier independently of the API tier, swap implementations without downtime, and extend the mesh with additional workers as the system grows.

| Worker             | Language   | Function                       | Does                                                                                          |
| ------------------ | ---------- | ------------------------------ | --------------------------------------------------------------------------------------------- |
| `inference-worker` | Python     | `inference::run_inference`     | Loads `gemma-3-270m` (GGUF, Q8) via `transformers`, applies the chat template to `messages`, and returns the decoded model output. |
| `caller-worker`    | TypeScript | `inference::get_response`      | Calls `inference::run_inference` with the incoming `messages` payload and returns the result. |
| `caller-worker`    | TypeScript | `http::run_inference_over_http` | HTTP trigger bound to `POST /v1/chat/completions`; forwards the request body to `inference::get_response` and returns a JSON HTTP response. |

For more details regarding implementation, find docs here: https://iii.dev/docs/

## Architecture

```text
                                 +-------------------------------------------------+
                                 |  AWS VPC (10.0.0.0/16)                          |
                                 |                                                 |
  +------------------+           |  +-------------------------------------------+  |
  |                  |           |  | Public Subnet (10.0.1.0/24)               |  |
  |  Public Internet |   HTTP    |  |                                           |  |
  |  (curl / JSON)   +---(80)----+->+  [Nginx Gateway Instance] (Reverse Proxy) |  |
  |                  |           |  |      | proxy_pass http://caller:3111      |  |
  +------------------+           |  |      v                                    |  |
                                 |  +-------------------------------------------+  |
                                 |                                                 |
                                 |  +-------------------------------------------+  |
                                 |  | Private Subnet 1 (10.0.2.0/24)            |  |
                                 |  |                                           |  |
                                 |  |  [Caller Worker Instance]                 |  |
                                 |  |   - iii-engine (Ports 3111, 49134)        |  |
                                 |  |   - caller-worker (Node.js)               |  |
                                 |  |      ^                                    |  |
                                 |  +------|------------------------------------+  |
                                 |         | RPC / WebSocket (Port 49134)          |
                                 |  +------|------------------------------------+  |
                                 |  | Private Subnet 2 (10.0.3.0/24)            |  |
                                 |  |      v                                    |  |
                                 |  |  [Inference Worker Instance]              |  |
                                 |  |   - inference-worker (Python + Gemma)     |  |
                                 |  |                                           |  |
                                 |  +-------------------------------------------+  |
                                 +-------------------------------------------------+
```

## How to Redeploy from Scratch

1. **Prerequisites**: Ensure you have `docker`, `terraform`, and the `aws` CLI installed and configured.
2. **Build and Push Custom Images**:
   Run the provided `build_and_push.sh` script to build the Docker images from the source code and push them to your Docker Hub repository.
   ```bash
   chmod +x build_and_push.sh
   ./build_and_push.sh
   # When prompted, enter your Docker Hub username (e.g., yourname)
   ```
3. **Provision the Infrastructure**:
   Navigate to the `terraform` directory and apply the configuration. You will need to pass your Docker Hub username so Terraform can pull the custom images you just pushed.
   ```bash
   cd terraform
   terraform init
   terraform apply -var="docker_username=<your-dockerhub-username>"
   ```
   *Note: Ensure you have an AWS SSH key pair named `llm-mesh-deployer-key` generated using the provided `terraform-key.pub`.*

4. **Testing**: 
   Terraform will output `nginx_public_ip` and `curl_test_command` when finished.

## API Usage

**Exact `curl` command:**
```bash
curl -s -X POST http://<NGINX_PUBLIC_IP>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Explain quantum computing in one short sentence."}]}'
```

**Sample Request:**
```json
{
  "messages": [
    {"role": "user", "content": "Explain quantum computing in one short sentence."}
  ]
}
```

**Sample Response:**
```json
{
  "result": {
    "text": "Quantum computing is a rapidly-emerging technology that harnesses the laws of quantum mechanics to solve problems too complex for classical computers.",
    "success": "You've connected two workers and they're interoperating seamlessly, now let's add a few more workers to expand this project's functionality."
  }
}
```

## Production Hardening & Scaling Writeup

**What to harden before production:**
1. **Security & Access Control**: The Nginx Gateway currently exposes port 80 (HTTP). This needs to be secured with TLS/SSL (HTTPS) using a valid certificate (e.g., Let's Encrypt or AWS ACM). Additionally, the API endpoints lack authentication. An API Gateway (like Kong or AWS API Gateway) or an authorization middleware in the TypeScript worker should be implemented to validate API keys/JWTs.
2. **Network Security**: SSH access (`port 22`) on the Nginx instance is currently open to `0.0.0.0/0`. This should be restricted to a specific VPN CIDR or corporate IP address. Better yet, SSH should be disabled entirely in favor of AWS Systems Manager (SSM) Session Manager.
3. **Observability & Logging**: While the iii-engine has an observability worker, logs are currently stored in memory or printed to stdout. For production, these should be forwarded to a centralized logging system like CloudWatch, Datadog, or an ELK stack. Container health checks and restart policies should be explicitly monitored.

**What to do differently if the model were 100x larger:**
If we were serving a large model (e.g., Llama 3 70B), the architecture would need significant changes:
1. **Hardware Acceleration**: The `t3.medium` CPU instances would be entirely insufficient. We would need GPU-accelerated instances (e.g., `g5` or `p4d` instances on AWS) and configure the Python inference worker to utilize CUDA and multiple GPUs via tensor parallelism (e.g., using vLLM or TGI).
2. **Inference Tier Scaling & Load Balancing**: A 100x larger model takes significantly longer to load and infer. We would decouple the inference workers further by deploying them inside an Auto Scaling Group (ASG) or a managed Kubernetes cluster (EKS) where they can horizontally scale based on queue depth.
3. **Asynchronous API**: Standard HTTP request timeouts (which are extended to 600s here) would still drop connections for large requests. The API would need to become asynchronous—the caller worker would immediately return a `job_id`, and the client would poll or receive a webhook/WebSocket push when the GPU inference completes.
