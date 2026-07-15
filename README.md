# GenAI Model Selection Demo

Educational demonstration of provider-agnostic GenAI architecture for AWS Technical Training.

## Overview

This demo showcases intelligent model selection and routing across multiple GenAI providers (Anthropic Claude, OpenAI GPT-OSS, AWS Nova) through a unified AWS Bedrock Converse API interface.

There are two demo pages:

- **Main demo** (`index.html`) - the full provider-agnostic architecture demo with health monitoring, routing strategies, and instructor-triggered failure simulation.
- **Smart Routing demo** (`smart-routing.html`, linked from the main demo's header) - a smaller, standalone demo showing complexity-based routing within a single model family (Claude Haiku / Sonnet / Opus).

See [ARCHITECTURE-WALKTHROUGH.md](ARCHITECTURE-WALKTHROUGH.md) for an instructor-facing trace of how a query flows through the codebase for both demos, and [STUDENT-GUIDE.md](STUDENT-GUIDE.md) for a student-facing explainer you can share or put on screen.

## Features

- **Provider-Agnostic Architecture**: Single interface works identically across all providers
- **Intelligent Routing**: Automatic model selection based on health, performance, and query characteristics
- **Instructor-Triggered Failover**: The "Instructor Controls" panel lets you simulate a provider going down and see routing adapt live
- **Real-time Monitoring**: Live provider status and performance metrics
- **Interactive Code Viewers**: Click architecture diagram components to see actual Lambda code

**Important limitation:** the failover/circuit-breaker behavior only activates for failures *simulated* through the Instructor Controls panel. A genuine runtime error calling Bedrock (wrong model ID, quota exceeded, region issue, etc.) is not automatically caught and retried against another provider - it surfaces as a 500 error to the user. Don't present this as "the system automatically recovers from any failure" - it recovers from the specific failures you trigger via the demo's admin panel.

## Quick Start

### Prerequisites

- AWS CLI configured with a profile that has an AWS region set (`aws configure get region --profile <your-profile>` should return something). Both `deploy-sam.sh` and `cleanup-deployment.sh` read the region from your active profile - there's no hardcoded region in this project.
- AWS SAM CLI installed ([Installation Guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html))
- **Bedrock model access enabled** in your target region for: Anthropic Claude Sonnet 4.5, Claude Haiku 4.5, Claude Opus 4.5, OpenAI GPT-OSS 120B, and Amazon Nova Pro/Lite/Micro. Check this in the Bedrock console under "Model access" before class - a missing model access grant will surface as a runtime error during the demo, not at deploy time.
- If using AWS IAM Identity Center (SSO), make sure your session is active (`aws sso login --profile <your-profile>`) before deploying - an expired session fails the deploy step with an SSO token error.

### Deployment

```bash
./deploy-sam.sh
```

The script will:
1. Build the Lambda function with dependencies
2. Deploy infrastructure using SAM, into whichever region your AWS profile is configured for
3. Upload website files to S3 (both `index.html`/`app.js` and `smart-routing.html`/`smart-routing.js`, patching the API URL into both)
4. Invalidate the CloudFront cache
5. Verify the deployment by curling the website and `/health` endpoint, and report the result
6. Display your website and API URLs

Re-running the script when there are no code changes is safe - it detects "no changes to deploy" from SAM and continues on to re-sync the website files rather than treating it as a failure.

### Manual Deployment

```bash
# Build
sam build

# Deploy
sam deploy --resolve-s3 --capabilities CAPABILITY_IAM

# Get outputs
aws cloudformation describe-stacks --stack-name genai-model-selection-demo \
    --query 'Stacks[0].Outputs'
```

Note: manual deployment does **not** patch the API URL into `web/app.js`/`web/smart-routing.js` or sync the website to S3 - you'd need to do those steps yourself (see the relevant section of `deploy-sam.sh` for the exact commands). Using `./deploy-sam.sh` is strongly recommended over manual deployment for this reason.

## Architecture

- **Frontend**: Static web app (HTML/CSS/JavaScript) served via CloudFront, backed by an S3 bucket
- **API**: API Gateway with Lambda integration (routes: `/query`, `/health`, `/metrics`, `/admin/simulate-failure`, `/smart-routing`)
- **Compute**: A single Python Lambda function handling both demos' logic
- **AI Providers**: AWS Bedrock Converse API (Anthropic Claude, OpenAI GPT-OSS, Amazon Nova)
- **Monitoring**: CloudWatch logs

**Note on API security:** the API Gateway endpoint has no authentication and permissive CORS (`*`). This is intentional for a classroom demo but means anyone with the URL can invoke it and incur Bedrock costs. Don't leave the stack deployed longer than needed - run `./cleanup-deployment.sh` after each class session.

## Project Structure

```
├── lambda/                    # Lambda function code
│   ├── lambda_handler.py      # Main handler (routes both demos)
│   ├── bedrock_adapter.py     # Unified Bedrock interface, all model IDs
│   ├── router.py              # Intelligent routing for the main demo
│   ├── health_monitor.py      # Health checks and circuit breakers
│   └── requirements.txt       # Python dependencies
├── web/                        # Frontend files
│   ├── index.html, app.js      # Main demo
│   ├── smart-routing.html/js/  # Smart-routing demo
│   └── styles.css
├── template.yaml               # SAM template
├── samconfig.toml              # SAM configuration (no hardcoded region)
├── deploy-sam.sh                # Deployment script
├── cleanup-deployment.sh        # Teardown script
├── ARCHITECTURE-WALKTHROUGH.md  # Instructor-facing code walkthrough
└── STUDENT-GUIDE.md             # Student-facing explainer
```

## Usage

1. Open the website URL provided after deployment
2. Submit queries through the main demo's interface
3. Watch automatic provider selection and routing
4. Use Instructor Controls to simulate a provider failure and see routing adapt
5. Click architecture diagram components to view code (hover for tooltips, click the Lambda Router or Bedrock boxes for a code viewer)
6. Follow the "Next demo" link in the header to try Smart Routing (Haiku/Sonnet/Opus tiering)

## Educational Value

This demo teaches:
- Provider-agnostic API design patterns (via Bedrock's Converse API)
- Cost/capability tiering within a single model family (Smart Routing demo)
- Intelligent routing algorithms
- Simulated circuit breaker and failover patterns
- Health monitoring and observability
- Serverless architecture on AWS

## Cleanup

### Automated Cleanup (Recommended)

```bash
# Run the cleanup script (handles everything automatically)
./cleanup-deployment.sh
```

The cleanup script will:
1. Resolve the AWS region from your active profile (same as `deploy-sam.sh`)
2. Empty the S3 bucket (required before deletion)
3. Delete the CloudFormation stack and wait for completion
4. Clean up local SAM artifacts

See [CLEANUP-GUIDE.md](CLEANUP-GUIDE.md) for detailed documentation.

The website bucket name includes a short unique suffix (derived from the stack ID) specifically so that deleting and redeploying repeatedly across class sessions doesn't hit S3 bucket name collisions with a bucket that was just deleted.

### Manual Cleanup

```bash
# Get your profile's region and the bucket name
REGION=$(aws configure get region)
BUCKET=$(aws cloudformation describe-stacks --stack-name genai-model-selection-demo \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`WebsiteBucket`].OutputValue' --output text)

# Empty S3 bucket first
aws s3 rm s3://${BUCKET}/ --recursive --region "$REGION"

# Delete the stack
aws cloudformation delete-stack --stack-name genai-model-selection-demo --region "$REGION"

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name genai-model-selection-demo --region "$REGION"
```

## License

Educational demonstration for AWS Technical Training.
