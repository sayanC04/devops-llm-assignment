#!/bin/bash
set -e

# Ask for Docker Hub username
read -p "Enter your Docker Hub username: " DOCKER_USER

if [ -z "$DOCKER_USER" ]; then
    echo "Docker Hub username cannot be empty."
    exit 1
fi

echo "Please log in to Docker Hub if you haven't already."
docker login

# Build and push Caller Worker
echo "Building Caller Worker..."
docker build -t $DOCKER_USER/caller-worker:latest ./workers/caller-worker
docker push $DOCKER_USER/caller-worker:latest

# Build and push Inference Worker
echo "Building Inference Worker..."
docker build -t $DOCKER_USER/inference-worker:latest ./workers/inference-worker
docker push $DOCKER_USER/inference-worker:latest

# Build and push Nginx
echo "Building Nginx Gateway..."
docker build -t $DOCKER_USER/nginx-serve:latest ./nginx
docker push $DOCKER_USER/nginx-serve:latest

echo "================================================="
echo "Done! All images have been built and pushed to Docker Hub."
echo "You can now deploy your infrastructure by updating terraform/variables.tf"
echo "with your Docker Hub username ($DOCKER_USER) or passing it during terraform apply:"
echo ""
echo "cd terraform"
echo "terraform init"
echo "terraform apply -var=\"docker_username=$DOCKER_USER\""
echo "================================================="
