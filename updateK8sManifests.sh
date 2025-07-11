#!/bin/bash

# Enable debugging output
set -x

# Ensure the environment variable `GITHUB_TOKEN` is passed from CodeBuild securely
if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: GITHUB_TOKEN environment variable not set."
  exit 1
fi

# Ensure the environment variables for ECR URL and image name are set
if [ -z "$ECR_URL" ] || [ -z "$IMAGE_NAME" ]; then
  echo "Error: ECR_URL or IMAGE_NAME environment variables not set."
  exit 1
fi

# Set the repository URL using the GitHub token
REPO_URL="https://$GITHUB_TOKEN@github.com/maddy00o7/example-voting-app.git"

# Clone the GitHub repository into the /tmp directory
echo "Cloning the repository..."
git clone "$REPO_URL" /tmp/temp_repo

# Navigate into the cloned repository directory
cd /tmp/temp_repo

# Make changes to the Kubernetes manifest file
# We're updating the image tag in result-deployment.yaml
echo "Modifying Kubernetes manifest..."
sed -i "s|image:.*|image: $ECR_URL/$IMAGE_NAME:$IMAGE_TAG|g" k8s-specifications/result-deployment.yaml

# Add the modified files to Git staging area
git add .

# Commit the changes
git commit -m "Update Kubernetes manifest with new image tag"

# Push the changes back to the GitHub repository
git push

# ECR authentication
echo "Authenticating to Amazon ECR..."
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin $ECR_URL

# Check existing tags in ECR to determine the next version tag
echo "Fetching existing image tags from ECR..."
EXISTING_TAGS=$(aws ecr describe-images --repository-name $IMAGE_NAME --query 'imageDetails[].imageTags' --output text)

# Extract the latest version (e.g., v1, v2, v3) and increment it
LATEST_TAG=$(echo "$EXISTING_TAGS" | grep -o 'v[0-9]*' | sort -V | tail -n 1)

# If no tags exist, set to v1
if [ -z "$LATEST_TAG" ]; then
  NEXT_TAG="v1"
else
  # Increment the tag number (e.g., v1 -> v2)
  NEXT_TAG=$(echo "$LATEST_TAG" | awk -F'v' '{print "v" $2+1}')
fi

echo "Next Docker image tag: $NEXT_TAG"

# Build the Docker image
echo "Building Docker image..."
docker build -t $IMAGE_NAME .

# Tag the Docker image for ECR
echo "Tagging Docker image for ECR..."
docker tag $IMAGE_NAME:latest $ECR_URL/$IMAGE_NAME:$NEXT_TAG

# Push the Docker image to ECR
echo "Pushing Docker image to ECR..."
docker push $ECR_URL/$IMAGE_NAME:$NEXT_TAG

# Cleanup: Remove the temporary cloned repository directory
echo "Cleaning up temporary files..."
rm -rf /tmp/temp_repo

echo "Deployment script completed."
