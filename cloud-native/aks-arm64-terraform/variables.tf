variable "location" {
  type        = string
  description = "Azure resource location"
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Deploy into this existing resource group; leave empty to create one."
  default     = ""
}

variable "tags" {
  type        = map(any)
  description = "Key/value pairs to store as resource tags"
  default = {
    source = "aka.ms/oss-labs"
    lab    = "aks-arm64-terraform"
  }
}