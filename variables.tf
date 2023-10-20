variable "base_name" {
  type        = string
  default     = "q3cc-app"
  description = "Only use lower case letters and numbers to make sure you don't try to provide invaluid chartacters for the bucket creation.  Used to name and tag resources."
}

variable "generic_tag_notes" {
  type        = string
  default     = "Created using Terraform code pulled from the Innovation launchpad building blocks repository."
  description = "Used to generate a unique and easy to identify set of notes that gets tagged for each resource that is created."
}

variable "ec2_key_name" {
  type        = string
  default = "q3ccappkey"
  description = " This is key pair that will be used to launch the EC2 instance.  Make sure it exists in the AWs account first and you have access to it."
}

variable "environment" {
  type        = string
  default     = "dev"
}
variable "org" {
  type        = string
  default     = "CC"
}

variable "project" {
  type        = string
  default     = "petclinic"
}

