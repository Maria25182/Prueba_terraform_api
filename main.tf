provider "aws" {
  region = "us-east-1"
}


resource "aws_dynamodb_table" "user_table" {
  name         = "user"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}


resource "aws_s3_bucket" "user_data_bucket" {
  bucket = "user-data-bucket-py"
  tags = {
    Name        = "pTecnic2"
    Environment = "Dev"
  }
}


resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.user_data_bucket.bucket
  key    = "GetUser.zip"
  source = "C:/Prueba_terraform_api/GetUser.zip" ##Review the route
}


resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com",
        },
      },
    ],
  })
}


resource "aws_iam_policy" "lambda_dynamodb_access_policy" {
  name        = "lambda_dynamodb_access_policy"
  description = "Allow Lambda to read from DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:Scan",
          "dynamodb:GetItem",
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.user_table.arn,
      },
    ],
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_access_policy.arn
}


resource "aws_lambda_function" "get_user_function" {
  function_name = "GetUserFunction"

  s3_bucket = aws_s3_bucket.user_data_bucket.bucket
  s3_key    = "GetUser.zip"
  handler   = "lambda_function.lambda_handler"
  runtime   = "python3.8"
  role      = aws_iam_role.lambda_execution_role.arn
}


resource "aws_iam_role" "api_gateway_role" {
  name = "api_gateway_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com",
        },
      },
    ],
  })
}


resource "aws_iam_policy" "api_gateway_lambda_invocation_policy" {
  name        = "api_gateway_lambda_invocation_policy"
  description = "Allow API Gateway to invoke Lambda"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "lambda:InvokeFunction",
        Effect   = "Allow",
        Resource = aws_lambda_function.get_user_function.arn,
      },
    ],
  })
}


resource "aws_iam_role_policy_attachment" "api_gateway_lambda_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_lambda_invocation_policy.arn
}


resource "aws_api_gateway_rest_api" "user_api" {
  name        = "UserAPI"
  description = "API for Lambda function"
}


resource "aws_api_gateway_resource" "device_resource" {
  rest_api_id = aws_api_gateway_rest_api.user_api.id
  parent_id   = aws_api_gateway_rest_api.user_api.root_resource_id
  path_part   = "device"
}


resource "aws_api_gateway_method" "get_device_method" {
  rest_api_id   = aws_api_gateway_rest_api.user_api.id
  resource_id   = aws_api_gateway_resource.device_resource.id
  http_method   = "GET"
  authorization = "NONE"
}


resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.user_api.id
  resource_id             = aws_api_gateway_resource.device_resource.id
  http_method             = aws_api_gateway_method.get_device_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_user_function.arn}/invocations"
}


resource "aws_lambda_permission" "api_gateway_lambda_permission" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_user_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.user_api.execution_arn}/*/*"
}


resource "aws_api_gateway_deployment" "dev_stage" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
  ]
  rest_api_id = aws_api_gateway_rest_api.user_api.id
  stage_name  = "dev"
}
