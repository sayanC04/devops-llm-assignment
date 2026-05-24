# 🌐 Distributed LLM Inference Mesh

![Docker](https://img.shields.io/badge/Docker-Ready-blue.svg)
![Terraform](https://img.shields.io/badge/Terraform-Infrastructure_as_Code-623CE4.svg)
![AWS](https://img.shields.io/badge/AWS-EC2_%7C_VPC-FF9900.svg)
![TypeScript](https://img.shields.io/badge/Worker-TypeScript-3178C6.svg)
![Python](https://img.shields.io/badge/Worker-Python-3776AB.svg)

A scalable, production-ready prototype that runs a Small Language Model (SLM) behind a distributed worker mesh. 

This architecture decouples the API tier from the Heavy-Compute Inference tier using a JSON-RPC mesh. The **Python inference worker** hosts the Gemma model and exposes inference as an RPC function, while the **TypeScript API worker** intercepts incoming HTTP requests, routes them to the RPC mesh, and formats the output. Because they are completely decoupled, you can scale the inference tier independently, swap implementations with zero downtime, and extend the mesh as the system grows.

---

## 🏗️ Architecture

The infrastructure is fully deployed on AWS using Terraform. Network hygiene is strictly enforced: workers sit in isolated private subnets and cannot be accessed directly from the public internet.

![Architecture Diagram](architecture.png)

### 🧩 Components

| Worker | Language | Function | Description |
| :--- | :--- | :--- | :--- |
| **`inference-worker`** | Python | `inference::run_inference` | Loads `gemma-3-270m` (GGUF, Q8), applies the chat template to `messages`, and returns the decoded LLM output. |
| **`caller-worker`** | TypeScript | `inference::get_response` | Calls `inference::run_inference` via RPC with the incoming payload and returns the result. |
| **`caller-worker`** | TypeScript | `http::run_inference_over_http` | HTTP trigger bound to `POST /v1/chat/completions`. Safely parses the HTTP body and forwards it to the RPC mesh. |

---

## 🚀 Quickstart & Deployment

### 1. Prerequisites
Ensure you have the following installed and authenticated on your local machine:
* `docker`
* `terraform`
* `aws-cli`

### 2. Prebuilt Docker Images
If you want to pull the pre-built images directly to test them locally, you can pull them from Docker Hub:
```bash
docker pull sayanC04/caller-worker:latest
docker pull sayanC04/inference-worker:latest
docker pull sayanC04/nginx-serve:latest
```

### 3. Build Your Own Images (Optional)
If you are modifying the source code, you can build and push the customized images to your own Docker Hub repository using the provided bash script:
```bash
chmod +x build_and_push.sh
./build_and_push.sh
# When prompted, enter your Docker Hub username
```

### 4. Deploy Infrastructure via Terraform
Deploy the entire AWS VPC, Subnets, Security Groups, and EC2 Instances using Terraform. 

*Note: You must have an AWS SSH key pair named `llm-mesh-deployer-key` generated using the provided `terraform-key.pub`.*
```bash
cd terraform
terraform init

# Pass your Docker Hub username so Terraform pulls your specific images
terraform apply -var="docker_username=sayanC04"
```
When Terraform completes, it will output the `nginx_public_ip` and an exact `curl_test_command` you can use to test the API!

---

## 📡 API Usage

Once deployed, the API acts similarly to the OpenAI chat completions endpoint. 

**Request:**
```bash
curl -s -X POST http://<NGINX_PUBLIC_IP>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Explain quantum computing in one short sentence."}]}'
```

**Response:**
```json
{
  "result": {
    "text": "Quantum computing is a rapidly-emerging technology that harnesses the laws of quantum mechanics to solve problems too complex for classical computers.",
    "success": "You've connected two workers and they're interoperating seamlessly, now let's add a few more workers to expand this project's functionality."
  }
}
```
*(Note: The first request may take ~30 seconds as the Python worker downloads and de-quantizes the Gemma model into RAM. Subsequent requests will be much faster).*

---

## 🛡️ Production Hardening & Scaling

Before launching this project to real users, we need to upgrade its security and prepare it for heavy traffic.

### 1. Making it Secure (Production Hardening)
- **HTTPS & Authentication**: Right now, the Nginx API is exposed over plain HTTP (Port 80) without any passwords. For production, we must add an SSL certificate (HTTPS) and require API Keys so only authorized users can send requests.
- **Locking Down SSH**: The port used to connect to the servers (Port 22) is open to the internet. We should restrict it so only our specific developer IP address can log in, or disable it entirely in favor of AWS Systems Manager.
- **Centralized Logging**: Currently, to read errors, we have to manually log into the servers and check Docker logs. We should automatically send all logs to a central dashboard like AWS CloudWatch or Datadog so we can monitor the system easily.

### 2. Scaling up for a 100x Larger AI Model
If we wanted to run a massive model like Llama-3 70B instead of the tiny Gemma model, the current setup would crash. Here is what we would change:
- **Switch to GPUs**: Regular CPU servers (`t3.medium`) are too slow. We would need to upgrade the Python worker to run on powerful AWS GPU instances (like `g5`) to handle the heavy AI computations.
- **Auto-Scaling**: A huge model takes longer to process requests. We would place the inference workers in an Auto Scaling Group (ASG). If hundreds of users ask questions at once, AWS would automatically spin up more Python workers to handle the load.
- **Background Processing**: Because big models take a long time to answer, standard HTTP requests will eventually time out. We would change the API so it instantly returns a `job_id`, and the user's app checks back a minute later to get the final answer.
