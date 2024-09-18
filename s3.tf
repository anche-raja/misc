provider "aws" {
  alias  = "east"
  region = "us-east-1"
}

provider "aws" {
  alias  = "west"
  region = "us-west-1"
}

resource "aws_kms_key" "s3_kms_east" {
  provider = aws.east
  description = "KMS key for encrypting S3 bucket in us-east-1"
}

resource "aws_kms_key" "s3_kms_west" {
  provider = aws.west
  description = "KMS key for encrypting S3 bucket in us-west-1"
}

resource "aws_kms_alias" "s3_alias_east" {
  provider = aws.east
  name     = "alias/s3-east-key"
  target_key_id = aws_kms_key.s3_kms_east.id
}

resource "aws_kms_alias" "s3_alias_west" {
  provider = aws.west
  name     = "alias/s3-west-key"
  target_key_id = aws_kms_key.s3_kms_west.id
}


resource "aws_s3_bucket" "source_bucket" {
  provider = aws.east
  bucket   = "my-source-bucket-east"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3_kms_east.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  versioning {
    enabled = true
  }

  tags = {
    Name = "Source Bucket"
    Environment = "Production"
  }
}

resource "aws_s3_bucket" "destination_bucket" {
  provider = aws.west
  bucket   = "my-destination-bucket-west"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3_kms_west.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  versioning {
    enabled = true
  }

  tags = {
    Name = "Destination Bucket"
    Environment = "Production"
  }
}





resource "aws_iam_role" "replication_role" {
  name = "s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "replication_policy" {
  role = aws_iam_role.replication_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ],
        Resource = [
          "${aws_s3_bucket.source_bucket.arn}/*",
        ]
      },
      {
        Effect   = "Allow",
        Action   = [
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.source_bucket.arn
        ]
      },
      {
        Effect   = "Allow",
        Action   = [
          "s3:PutObject"
        ],
        Resource = "${aws_s3_bucket.destination_bucket.arn}/*"
      }
    ]
  })
}






resource "aws_s3_bucket_replication_configuration" "replication_config" {
  provider = aws.east
  bucket   = aws_s3_bucket.source_bucket.bucket

  role     = aws_iam_role.replication_role.arn

  rules {
    id     = "ReplicationRule"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.destination_bucket.arn
      storage_class = "STANDARD"
      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.s3_kms_west.arn
      }
    }

    filter {
      prefix = ""
    }
  }
}




resource "aws_s3_bucket_policy" "source_bucket_policy" {
  provider = aws.east
  bucket   = aws_s3_bucket.source_bucket.bucket

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.source_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "destination_bucket_policy" {
  provider = aws.west
  bucket   = aws_s3_bucket.destination_bucket.bucket

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.destination_bucket.arn}/*"
      }
    ]
  })
}



