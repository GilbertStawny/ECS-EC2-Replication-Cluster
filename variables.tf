variable "clusterName" {
  type        = string
  description = "What is the name of your ECS cluster?"
}

variable "creator" {
  type        = string
  description = "Name of the LW Engineer creating these resources?"
  validation {
    condition     = length(var.creator) > 2
    error_message = "Please use your full first or last name, to be identifiable."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR range used by the new VPC."
}

variable "private_subnets_cidr" {
  type        = list(any)
  description = "CIDR range used by new private subnet and NAT"
}

variable "public_subnets_cidr" {
  type        = list(any)
  description = "CIDR range used by new public subnet and IGW"
}

variable "region" {
  description = "AWS Deployment region."
}

variable "availability_zones" {
  type        = list(any)
  description = "List of available AZs for subnets"
}
