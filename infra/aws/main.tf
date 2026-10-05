terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "bucket_name" {
  type    = string
  default = "data-lake-dev"
}

# Points at the emulator (kubectl port-forward -> localhost:4566).
# For real AWS: delete the endpoints/skip_* lines and use real credentials.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    s3  = "http://localhost:4566"
    iam = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "lake" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_versioning" "lake" {
  bucket = aws_s3_bucket.lake.id
  versioning_configuration { status = "Enabled" }
}

# Least privilege: only this bucket, only the actions the API needs.
data "aws_iam_policy_document" "api_s3" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.lake.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.lake.arn}/*"]
  }
}

resource "aws_iam_policy" "api_s3" {
  name   = "data-api-s3-access"
  policy = data.aws_iam_policy_document.api_s3.json
}

# Trust policy shaped for IRSA. On real EKS, replace the principal with the
# cluster OIDC provider and scope `sub` to system:serviceaccount:data:data-api.
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"]
    }
    condition {
      test     = "StringEquals"
      variable = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE:sub"
      values   = ["system:serviceaccount:data:data-api"]
    }
  }
}

resource "aws_iam_role" "api" {
  name               = "data-api-role"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy_attachment" "api" {
  role       = aws_iam_role.api.name
  policy_arn = aws_iam_policy.api_s3.arn
}

output "bucket" { value = aws_s3_bucket.lake.bucket }
output "role_arn" { value = aws_iam_role.api.arn }
