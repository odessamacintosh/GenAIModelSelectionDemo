#!/bin/bash

# Disable the AWS CLI pager so output prints directly instead of opening an
# interactive pager (which can make this script look like it's hung).
export AWS_PAGER=""

# Resolve the region from the active AWS CLI profile/config. `sam deploy`
# below also relies on this (samconfig.toml no longer hardcodes a region),
# so this script and the actual deployed stack always agree on where things
# live, instead of silently drifting apart like they did before.
REGION=$(aws configure get region)
if [ -z "$REGION" ]; then
    echo "❌ Could not determine AWS region from your CLI profile."
    echo "   Set one with: aws configure set region <region>"
    echo "   or export AWS_REGION=<region> before running this script."
    exit 1
fi
echo "Using region: $REGION"
echo ""

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
DEPLOY_OUTPUT=$(sam deploy --resolve-s3 --no-confirm-changeset --capabilities CAPABILITY_IAM 2>&1)
DEPLOY_EXIT_CODE=$?
echo "$DEPLOY_OUTPUT"

if [ $DEPLOY_EXIT_CODE -ne 0 ]; then
    # "No changes to deploy" isn't a real failure - it means the stack is
    # already up to date (e.g. re-running this script with no code changes).
    # Treat that case as success and continue to Step 3 so the website
    # files still get synced; any other error is a real failure.
    if echo "$DEPLOY_OUTPUT" | grep -q "No changes to deploy"; then
        echo "ℹ️  Stack is already up to date, no CloudFormation changes needed."
    else
        echo "❌ Deployment failed!"
        exit 1
    fi
fi

echo "✅ Deployment complete!"
echo ""

# Step 3: Get outputs and upload website
echo "Step 3/3: Configuring website..."

# Get API URL
API_URL=$(aws cloudformation describe-stacks \
    --stack-name genai-model-selection-demo \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
    --output text)

if [ -z "$API_URL" ] || [ "$API_URL" == "None" ]; then
    echo "❌ Failed to retrieve API URL from CloudFormation outputs. Aborting."
    exit 1
fi

# Get S3 bucket name
BUCKET=$(aws cloudformation describe-stacks \
    --stack-name genai-model-selection-demo \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`WebsiteBucket`].OutputValue' \
    --output text)

if [ -z "$BUCKET" ] || [ "$BUCKET" == "None" ]; then
    echo "❌ Failed to retrieve S3 bucket name from CloudFormation outputs. Aborting."
    exit 1
fi

# Get Website URL
WEBSITE_URL=$(aws cloudformation describe-stacks \
    --stack-name genai-model-selection-demo \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`WebsiteURL`].OutputValue' \
    --output text)

if [ -z "$WEBSITE_URL" ] || [ "$WEBSITE_URL" == "None" ]; then
    echo "❌ Failed to retrieve website URL from CloudFormation outputs. Aborting."
    exit 1
fi

# Get CloudFront Distribution ID
DIST_ID=$(aws cloudformation describe-stack-resources \
    --stack-name genai-model-selection-demo \
    --region "$REGION" \
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
if ! aws s3 sync web/ s3://${BUCKET}/ --region "$REGION" --exclude "*.bak" --exclude "__pycache__/*"; then
    echo "❌ Failed to sync website files to S3. Aborting."
    exit 1
fi

# Invalidate CloudFront cache (CloudFront is a global service, but the CLI
# call itself is region-agnostic aside from needing a region configured)
echo "Invalidating CloudFront cache..."
if ! aws cloudfront create-invalidation --distribution-id ${DIST_ID} --paths "/*" --region "$REGION" > /dev/null; then
    echo "⚠️  Warning: CloudFront invalidation failed. The site may serve stale content until the cache naturally expires."
fi

echo ""
echo "Verifying deployment..."

API_HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/health")
if [ "$API_HEALTH_STATUS" == "200" ]; then
    echo "✅ API health check passed ($API_HEALTH_STATUS)"
else
    echo "⚠️  API health check returned $API_HEALTH_STATUS (expected 200)"
fi

WEBSITE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$WEBSITE_URL")
if [ "$WEBSITE_STATUS" == "200" ]; then
    echo "✅ Website is serving content ($WEBSITE_STATUS)"
else
    echo "⚠️  Website returned $WEBSITE_STATUS (expected 200) - CloudFront cache may still be clearing, or web/ files may not have synced"
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
