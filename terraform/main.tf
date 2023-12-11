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
  alias = "main"
  region = "us-east-1"
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket_prefix = "terra-tick"
}


resource "aws_s3_object" "lambda_deployment" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "lambda_deployment.zip"
  source = "../app/dev.zip"
  etag = filemd5("../app/dev.zip")
}

resource "aws_lambda_function" "terra_tick" {
  function_name = "TerraTick"
  runtime = "python3.10"
  handler = "handler.lambda_handler"
  timeout = 30
  source_code_hash = filebase64sha256("../app/dev.zip")
  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_deployment.key
  role = aws_iam_role.lambda_execution_role.arn
}

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

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


resource "aws_iam_role" "lambda_execution_role" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_api_gateway_rest_api" "apigw" {
  name        = "terra-tick-api"
}

resource "aws_api_gateway_resource" "proxy_resource" {
  parent_id   = aws_api_gateway_rest_api.apigw.root_resource_id
  path_part   = "{proxy+}"
  rest_api_id = aws_api_gateway_rest_api.apigw.id
}

resource "aws_api_gateway_method" "any_method_root" {
  rest_api_id = aws_api_gateway_rest_api.apigw.id
  resource_id = aws_api_gateway_rest_api.apigw.root_resource_id
  http_method = "ANY"
    authorization = "NONE"

}

resource "aws_api_gateway_method" "any_method_proxy" {
  rest_api_id = aws_api_gateway_rest_api.apigw.id
    authorization = "NONE"
  resource_id = aws_api_gateway_resource.proxy_resource.id
  http_method = "ANY"
}

 resource "aws_api_gateway_integration" "proxy_integration" { 
    rest_api_id = aws_api_gateway_rest_api.apigw.id
    resource_id = aws_api_gateway_resource.proxy_resource.id
    uri = aws_lambda_function.terra_tick.invoke_arn
    type                   = "AWS_PROXY"
    http_method = aws_api_gateway_method.any_method_proxy.http_method
    passthrough_behavior   = "NEVER"
    integration_http_method = "POST"
  }

   resource "aws_api_gateway_integration" "root_integration" { 
    rest_api_id = aws_api_gateway_rest_api.apigw.id
    resource_id = aws_api_gateway_rest_api.apigw.root_resource_id
    uri = aws_lambda_function.terra_tick.invoke_arn
    type                   = "AWS_PROXY"
    http_method = aws_api_gateway_method.any_method_root.http_method
    passthrough_behavior   = "NEVER"
    integration_http_method = "POST"
  }

resource "aws_api_gateway_deployment" "app_deployment" {
  rest_api_id = aws_api_gateway_rest_api.apigw.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.apigw.root_resource_id,
      aws_api_gateway_resource.proxy_resource.id,
      aws_api_gateway_method.any_method_root.id,
      aws_api_gateway_method.any_method_proxy.id,
      aws_api_gateway_integration.root_integration.id,
      aws_api_gateway_integration.proxy_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "app_stage" {
  deployment_id = aws_api_gateway_deployment.app_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.apigw.id
  stage_name    = "dev"
}

resource "aws_lambda_permission" "app_api_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.terra_tick.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.apigw.execution_arn}/*/*"
}

output "app_url" {
  description = "Base URL for API Gateway stage."

  value = aws_api_gateway_stage.app_stage.invoke_url
}


output "function_name" {
  description = "Name of the Lambda function."

  value = aws_lambda_function.terra_tick.function_name
}
