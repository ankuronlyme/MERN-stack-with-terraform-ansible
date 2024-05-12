variable "aws_key_pair_name" {
  description = "Name of the AWS SSH key pair used for authentication"
  type = string
  default = "tm_key"
}

variable "app_server_count" {
  description = "Number of the AWS Instance Count"
  type = number
  default = 1
}

variable "database_server_count" {
  description = "Number of the AWS Instance Count"
  type = number
  default = 1
}