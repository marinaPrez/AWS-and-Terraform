terraform {
  backend "s3" {
    bucket = "terraform-bucket-maya"
    key    = "global/s3/terraform.tfstate"
    dynamodb_table = "terraform_dynamodb_marina"
    region = "us-west-2"
  }
}

