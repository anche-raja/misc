provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "us-west-1"
  region = "us-west-1"
}
======================================================================
modules/dynamodb/variables.tf

variable "table_name" {
  description = "The name of the DynamoDB table"
  type        = string
}

variable "hash_key" {
  description = "The hash key (primary key) for the DynamoDB table"
  type        = string
}

variable "range_key" {
  description = "The range key (sort key) for the DynamoDB table"
  type        = string
  default     = null
}

variable "read_capacity" {
  description = "The read capacity for the DynamoDB table"
  type        = number
  default     = 5
}

variable "write_capacity" {
  description = "The write capacity for the DynamoDB table"
  type        = number
  default     = 5
}

variable "global_secondary_indexes" {
  description = "List of global secondary indexes for the DynamoDB table"
  type = list(object({
    name               = string
    hash_key           = string
    range_key          = string
    projection_type    = string
    non_key_attributes = optional(list(string), [])
    read_capacity      = number
    write_capacity     = number
  }))
  default = []
}

variable "local_secondary_index" {
  description = "The local secondary index for the DynamoDB table"
  type = object({
    name               = string
    range_key          = string
    projection_type    = string
    non_key_attributes = optional(list(string), [])
  })
  default = null
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key to be used for encryption"
  type        = string
}

variable "tags" {
  description = "Tags to apply to the DynamoDB table"
  type        = map(string)
  default     = {}
}

=====================================
main.tf

resource "aws_dynamodb_table" "this" {
  name           = var.table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = var.read_capacity
  write_capacity = var.write_capacity
  hash_key       = var.hash_key

  dynamic "range_key" {
    for_each = var.range_key != null ? [var.range_key] : []
    content {
      name = range_key.value
      type = "S"
    }
  }

  attribute {
    name = var.hash_key
    type = "S"
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = global_secondary_index.value.projection_type
      read_capacity   = global_secondary_index.value.read_capacity
      write_capacity  = global_secondary_index.value.write_capacity

      dynamic "non_key_attributes" {
        for_each = global_secondary_index.value.projection_type == "INCLUDE" ? global_secondary_index.value.non_key_attributes : []
        content {
          non_key_attributes = non_key_attributes.value
        }
      }
    }
  }

  dynamic "local_secondary_index" {
    for_each = var.local_secondary_index != null ? [var.local_secondary_index] : []
    content {
      name            = local_secondary_index.value.name
      range_key       = local_secondary_index.value.range_key
      projection_type = local_secondary_index.value.projection_type

      dynamic "non_key_attributes" {
        for_each = local_secondary_index.value.projection_type == "INCLUDE" ? local_secondary_index.value.non_key_attributes : []
        content {
          non_key_attributes = non_key_attributes.value
        }
      }
    }
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = var.tags
}
