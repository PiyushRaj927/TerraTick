terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.17.0"
    }
  }

  required_version = "~> 1.2"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket_prefix = "terra-tick"
}


resource "aws_s3_object" "lambda_hello_world" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "hello-world.zip"
  source = "../app/dev.zip"
  # source = data.archive_file.lambda_hello_world.output_path

  etag = filemd5("../app/dev.zip")
}

resource "aws_lambda_function" "hello_world" {
  function_name = "TerraTick"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_hello_world.key

  runtime = "python3.10"
  handler = "handler.lambda_handler"
  timeout = 30
  source_code_hash = filebase64sha256("../app/dev.zip")

  role = aws_iam_role.lambda_exec.arn
}


resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# resource "aws_cloudwatch_log_group" "hello_world" {
#   name = "/aws/lambda/${aws_lambda_function.hello_world.function_name}"

#   retention_in_days = 30
# }

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}


resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "dev"
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
      end = "$context.awsEndpointRequestId"
      end2 = "$context.awsEndpointRequestId2"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "hello_world" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.hello_world.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  request_parameters = {
    "overwrite:path"    = "$request.path"
  }
}

# resource "aws_apigatewayv2_route" "hello_world" {
#   api_id = aws_apigatewayv2_api.lambda.id
#   # route_key = "$default"
#   route_key = "ANY /{proxy+}"
#   target    = "integrations/${aws_apigatewayv2_integration.hello_world.id}"
# }
resource "aws_apigatewayv2_route" "hello_world" {
  api_id = aws_apigatewayv2_api.lambda.id
  # route_key = "$default"
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.hello_world.id}"
}


resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_world.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

output "app_url" {
  description = "Base URL for API Gateway stage."

  value = aws_apigatewayv2_stage.lambda.invoke_url
}


output "function_name" {
  description = "Name of the Lambda function."

  value = aws_lambda_function.hello_world.function_name
}
