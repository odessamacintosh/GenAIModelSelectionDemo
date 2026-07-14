#!/bin/bash

# Disable the AWS CLI pager so output prints directly instead of opening an
# interactive pager (which can make this script look like it's hung).
export AWS_PAGER=""

echo "=========================================="
echo "  GenAI Demo - SAM Deployment Script     "
echo "=========================================="
echo ""
echo "This script deploys the GenAI Model Selection Demo using AWS SAM"
echo "for easy, instructor-friendly deployment."
echo ""

# Step 1: Build
echo "Step 1/3: Building Lambda function..."
sam build

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo "✅ Build complete!"
echo ""

# Step 2: Deploy
echo "Step 2/3: Deploying to AWS..."
sam deploy --resolve-s3 --no-confirm-changeset --capabilities CAPABILITY_IAM

if [ $? -ne 0 ]; then
    echo "❌ Deployment failed!"
    exit 1
fi

echo "✅ Deployment complete!"
echo ""

# Step 3: Get outputs and upload website
echo "Step 3/3: Configuring website..."

# Get API URL
API_URL=$(aws cloudformation describe-stacks \
    --stack-name genai-model-selection-demo \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
    --output text)

if [ -z "$API_URL" ] || [ "$API_URL" == "None" ]; then
    echo "❌ Failed to retrieve API URL from CloudFormation outputs. Aborting."
    exit 1
fi

# Get S3 bucket name
BUCKET=$(aws cloudformation describe-stacks \
    --stack-name genai-model-selection-demo \
    --query 'Stacks[0].Outputs[?OutputKey==`WebsiteBucket`].OutputValue' \
    --output text)

if [ -z "$BUCKET" ] || [ "$BUCKET" == "None" ]; then
    echo "❌ Failed to retrieve S3 bucket name from CloudFormation outputs. Aborting."
    exit 1
fi

# Get Website URL
WEBSITE_URL=$(aws cloudformation describe-stacks \
    --stack-name genai-model-selection-demo \
    --query 'Stacks[0].Outputs[?OutputKey==`WebsiteURL`].OutputValue' \
    --output text)

if [ -z "$WEBSITE_URL" ] || [ "$WEBSITE_URL" == "None" ]; then
    echo "❌ Failed to retrieve website URL from CloudFormation outputs. Aborting."
    exit 1
fi

# Get CloudFront Distribution ID
DIST_ID=$(aws cloudformation describe-stack-resources \
    --stack-name genai-model-selection-demo \
    --query 'StackResources[?ResourceType==`AWS::CloudFront::Distribution`].PhysicalResourceId' \
    --output text)

if [ -z "$DIST_ID" ] || [ "$DIST_ID" == "None" ]; then
    echo "❌ Failed to retrieve CloudFront distribution ID. Aborting."
    exit 1
fi

echo "API URL: $API_URL"
echo "S3 Bucket: $BUCKET"
echo "Website URL: $WEBSITE_URL"
echo ""

# Update web app(s) with the API URL. Both the main demo (app.js) and the
# smart-routing demo (smart-routing.js) have their own apiBaseUrl placeholder.
echo "Updating web app configuration..."
sed -i.bak "s|apiBaseUrl: 'https://[^']*'|apiBaseUrl: '${API_URL}'|g" web/app.js
sed -i.bak "s|apiBaseUrl = 'https://[^']*'|apiBaseUrl = '${API_URL}'|g" web/smart-routing.js
rm -f web/app.js.bak web/smart-routing.js.bak

# Upload website files
echo "Uploading website files to S3..."
if ! aws s3 sync web/ s3://${BUCKET}/ --exclude "*.bak" --exclude "__pycache__/*"; then
    echo "❌ Failed to sync website files to S3. Aborting."
    exit 1
fi

# Invalidate CloudFront cache
echo "Invalidating CloudFront cache..."
if ! aws cloudfront create-invalidation --distribution-id ${DIST_ID} --paths "/*" > /dev/null; then
    echo "⚠️  Warning: CloudFront invalidation failed. The site may serve stale content until the cache naturally expires."
fi

echo ""
echo "=========================================="
echo "  🎉 DEPLOYMENT COMPLETE!                "
echo "=========================================="
echo ""
echo "🌐 Website URL: $WEBSITE_URL"
echo "🔗 API URL: $API_URL"
echo ""
echo "Wait 1-2 minutes for CloudFront cache to clear, then open the website!"
echo ""
