provider "aws" {
  region = "us-east-1"
}

# Crear tabla DynamoDB
resource "aws_dynamodb_table" "user_table" {
  name         = "user"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# Crear bucket S3
resource "aws_s3_bucket" "user_data_bucket" {
  bucket = "user-data-bucket-py"
  tags = {
    Name        = "pTecnic2"
    Environment = "Dev"
  }
}

# Subir el archivo ZIP de Lambda al bucket S3
resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.user_data_bucket.bucket
  key    = "GetUser.zip"
  source = "C:/Terraform_Lambda/GetUser.zip"
}

# Crear rol IAM para Lambda
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

# Crear política IAM para acceso a DynamoDB
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

# Adjuntar política al rol de Lambda
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_access_policy.arn
}

# Crear función Lambda
resource "aws_lambda_function" "get_user_function" {
  function_name = "GetUserFunction"

  s3_bucket = aws_s3_bucket.user_data_bucket.bucket
  s3_key    = "GetUser.zip"
  handler   = "lambda_function.lambda_handler"
  runtime   = "python3.8"
  role      = aws_iam_role.lambda_execution_role.arn
}

# Crear rol IAM para API Gateway
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

# Crear política para permitir a API Gateway invocar Lambda
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

# Adjuntar política al rol de API Gateway
resource "aws_iam_role_policy_attachment" "api_gateway_lambda_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_lambda_invocation_policy.arn
}

# Crear API Gateway
resource "aws_api_gateway_rest_api" "user_api" {
  name        = "UserAPI"
  description = "API for Lambda function"
}

# Crear recurso en API Gateway
resource "aws_api_gateway_resource" "device_resource" {
  rest_api_id = aws_api_gateway_rest_api.user_api.id
  parent_id   = aws_api_gateway_rest_api.user_api.root_resource_id
  path_part   = "device"
}

# Crear método GET en el recurso
resource "aws_api_gateway_method" "get_device_method" {
  rest_api_id   = aws_api_gateway_rest_api.user_api.id
  resource_id   = aws_api_gateway_resource.device_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integrar Lambda con API Gateway
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.user_api.id
  resource_id             = aws_api_gateway_resource.device_resource.id
  http_method             = aws_api_gateway_method.get_device_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_user_function.arn}/invocations"
}

# Permitir que API Gateway invoque Lambda
resource "aws_lambda_permission" "api_gateway_lambda_permission" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_user_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.user_api.execution_arn}/*/*"
}

# Crear despliegue en API Gateway
resource "aws_api_gateway_deployment" "dev_stage" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
  ]
  rest_api_id = aws_api_gateway_rest_api.user_api.id
  stage_name  = "dev"
}
