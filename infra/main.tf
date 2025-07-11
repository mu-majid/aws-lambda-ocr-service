data "archive_file" "proxy_service" {
  type = "zip"

  source_dir  = "${path.module}/../proxy_service"
  output_path = "${path.module}/../proxy.zip"
}

resource "aws_s3_object" "proxy_service" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "proxy.zip"
  source = data.archive_file.proxy_service.output_path

  etag = filemd5(data.archive_file.proxy_service.output_path)
}

data "archive_file" "text_service" {
  type = "zip"

  source_dir  = "${path.module}/../text_recognition_service"
  output_path = "${path.module}/../text.zip"
}

resource "aws_s3_object" "text_service" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "text.zip"
  source = data.archive_file.text_service.output_path

  etag = filemd5(data.archive_file.text_service.output_path)
}

# Bucket Creation
resource "random_pet" "lambda_bucket_name" {
  prefix = "lambda-functions-gw"
  length = 4
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = random_pet.lambda_bucket_name.id
}

resource "aws_s3_bucket_ownership_controls" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "lambda_bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.lambda_bucket]

  bucket = aws_s3_bucket.lambda_bucket.id
  acl    = "private"
}

# IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "serverless_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_ocr_policy" {
  name = "lambda-ocr-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "textract:DetectDocumentText",
          "textract:AnalyzeDocument"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectText"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ocr_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_ocr_policy.arn
}


# Target Lambda - TextRecog
resource "aws_lambda_function" "target_lambda" {
  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.text_service.key
  function_name = "target-lambda"
  role         = aws_iam_role.lambda_role.arn
  handler      = "index.handler"
  runtime      = "nodejs18.x"
  timeout      = 60
  memory_size = 1024
  source_code_hash = data.archive_file.text_service.output_base64sha256

  depends_on = [ aws_s3_object.text_service ]
}

resource "aws_cloudwatch_log_group" "target_lambda" {
  name = "/aws/lambda/${aws_lambda_function.target_lambda.function_name}"

  retention_in_days = 30
}

# Caller Lambda - Proxy
resource "aws_lambda_function" "caller_lambda" {
  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.proxy_service.key
  function_name = "caller-lambda"
  role         = aws_iam_role.lambda_role.arn
  handler      = "index.handler"
  runtime      = "nodejs18.x"
  timeout      = 60
  source_code_hash = data.archive_file.proxy_service.output_base64sha256


  environment {
    variables = {
      TARGET_LAMBDA_FUNCTION_NAME = aws_lambda_function.target_lambda.function_name
    }
  }

  depends_on = [ aws_lambda_function.target_lambda, aws_s3_object.proxy_service ]
}

resource "aws_cloudwatch_log_group" "caller_lambda" {
  name = "/aws/lambda/${aws_lambda_function.caller_lambda.function_name}"

  retention_in_days = 30
}

# API Gateway
resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id
  name        = "serverless_lambda_stage"
  auto_deploy = true
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "caller_lambda" {
  api_id = aws_apigatewayv2_api.lambda.id
  integration_uri    = aws_lambda_function.caller_lambda.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "process" {
  api_id = aws_apigatewayv2_api.lambda.id
  route_key = "POST /process"
  target    = "integrations/${aws_apigatewayv2_integration.caller_lambda.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"
  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.caller_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

