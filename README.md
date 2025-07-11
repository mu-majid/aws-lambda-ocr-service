# AWS Lambda OCR Service

A serverless OCR (Optical Character Recognition) service built with AWS Lambda, API Gateway, Textract, and Rekognition that processes base64 images and returns the text with highest confidence score.

## Architecture

```
API Gateway → Caller Lambda → Target Lambda → AWS Textract + Rekognition
```

- **Caller Lambda** (`proxy_service`): Receives HTTP requests and invokes target Lambda
- **Target Lambda** (`text_recognition_service`): Performs dual OCR using AWS Textract and Rekognition
- **API Gateway v2**: HTTP API endpoint for external access

## Features

- **Dual OCR Processing**: Uses both AWS Textract and Rekognition for maximum accuracy
- **Confidence Scoring**: Returns result with highest confidence score
- **Base64 Image Input**: Accepts images as base64 strings via HTTP POST
- **Error Handling**: Graceful fallback if one OCR service fails
- **CloudWatch Logging**: Full request/response logging for debugging

## Quick Start

### Prerequisites

- AWS CLI configured
- Terraform installed
- Node.js 18+ installed

### Directory Structure

```
project/
├── main.tf
├── proxy_service/
│   └── index.js
└── text_recognition_service/
    ├── index.js
    ├── package.json
    └── node_modules/
```

### Lambda to Lambda communication

#### Comparison Table

| Method | Latency | Coupling | Scalability | Cost | Complexity | Use Case |
|--------|---------|----------|-------------|------|------------|----------|
| **Direct Invoke** | **Low** | High | Medium | Low | Low | Simple request/response |
| **SQS** | Medium | **Low** | **High** | Low | Medium | Decoupled async processing |
| **SNS** | Medium | **Low** | **High** | Low | Medium | Fan-out notifications |
| **EventBridge** | Medium | **Low** | **High** | Medium | Medium | Event-driven architecture |
| **Kinesis** | Medium | **Low** | **Very High** | Medium | High | Stream processing |
| **DynamoDB Streams** | Medium | **Low** | **High** | Low | Medium | Data change reactions |
| **S3 Events** | Medium | **Low** | **High** | Low | Low | File processing |
| **API Gateway** | Medium | Medium | **High** | Medium | Medium | HTTP-based communication |
| **Step Functions** | Medium | **Low** | **High** | High | High | Complex workflows |
| **Destinations** | **Low** | Medium | Medium | Low | Low | Success/failure routing |

Best Practices by Use Case:

Simple sync communication: Direct invoke (RequestResponse)
Async processing: SQS or SNS
Event-driven architecture: EventBridge
High-throughput streaming: Kinesis
Complex workflows: Step Functions
File processing: S3 Events
Web APIs: API Gateway
Database triggers: DynamoDB Streams

I have used direct Invoke for simplicity.

### Setup

1. **Install dependencies:**
```bash
cd text_recognition_service
npm install
cd ..
```

2. **Deploy infrastructure:**
```bash
terraform init
terraform apply
```

3. **Get API URL:**
```bash
terraform output api_url
```

## Usage

### API Endpoint

```
POST https://your-api-url/serverless_lambda_stage/process
Content-Type: application/json

{
  "image": "base64_encoded_image_string"
}
```

### Example Request

```bash
curl -X POST https://your-api-url/serverless_lambda_stage/process \
  -H "Content-Type: application/json" \
  -d '{"image": "iVBORw0KGgoAAAANSUhEUgAAAZAAAADI..."}'
```

### Example Response

```json
{
  "message": "Image processed successfully",
  "result": {
    "success": true,
    "data": {
      "bestResult": {
        "source": "textract",
        "text": "Hello World Document",
        "confidence": 0.95,
        "wordCount": 3
      },
      "allResults": [
        {
          "success": true,
          "source": "textract",
          "text": "Hello World Document",
          "confidence": 0.95,
          "wordCount": 3
        },
        {
          "success": true,
          "source": "rekognition",
          "text": "Hello World Document",
          "confidence": 0.87,
          "wordCount": 3
        }
      ],
      "processingInfo": {
        "imageSize": 15420,
        "imageType": "jpeg",
        "timestamp": "2025-01-11T14:30:00.000Z",
        "servicesUsed": ["textract", "rekognition"]
      }
    }
  }
}
```

## Configuration

### Environment Variables

- `TARGET_LAMBDA_FUNCTION_NAME`: Auto-configured by Terraform
- `AWS_REGION`: Set to `eu-central-1`

### AWS Resources Created

- 2x Lambda functions (caller + target)
- API Gateway v2 (HTTP API)
- S3 bucket for Lambda code storage
- IAM roles and policies
- CloudWatch log groups

### Permissions Required

- `lambda:InvokeFunction`
- `textract:DetectDocumentText`
- `rekognition:DetectText`
- `logs:*`

## Monitoring

### CloudWatch Logs

- **Caller Lambda**: `/aws/lambda/caller-lambda`
- **Target Lambda**: `/aws/lambda/target-lambda`
- **API Gateway**: `/aws/api_gw/serverless_lambda_gw`

### View Logs

```bash
# Get log URLs
terraform output caller_lambda_logs
terraform output target_lambda_logs
```

## Cost Optimization

- **Textract**: ~$1.50 per 1000 pages
- **Rekognition**: ~$1.00 per 1000 images
- **Lambda**: Pay per invocation + execution time
- **API Gateway**: Pay per request

## Troubleshooting

### Common Issues

1. **Internal Server Error**
   - Check CloudWatch logs for detailed error messages
   - Verify IAM permissions for Textract/Rekognition

2. **Code Not Updating**
   - Ensure `source_code_hash` is set in Terraform
   - Force update: `terraform apply -target=aws_lambda_function.target_lambda`

3. **OCR Not Working**
   - Verify image is valid base64
   - Check image format (supports PNG, JPEG, GIF)
   - Ensure image size < 5MB for Textract, < 5MB for Rekognition

### Debug Commands

```bash
# Check Terraform plan
terraform plan

# View current Lambda code
aws lambda get-function --function-name target-lambda

# Test Lambda directly
aws lambda invoke --function-name target-lambda \
  --payload '{"image":"base64string"}' response.json
```

## Development

### Local Testing

Test individual components:

```bash
# Test image generation
# Use the provided HTML tool to generate base64 test images

# Test Lambda locally (with AWS SAM)
sam local invoke target-lambda -e test-event.json
```

### Adding New OCR Services

1. Add new OCR function in `text_recognition_service/index.js`
2. Update `Promise.allSettled` array
3. Add required IAM permissions
4. Update `processOCRResults` function

## License

MIT License

