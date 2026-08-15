variable "environment_virtual_network" {
  type = object({
    use_custom_vnet = bool
    is_internal     = bool
  })
  description = "Bring your own custom VNET to ACA? If yes, specify if it will be internal only or external."
  default = {
    is_internal     = false
    use_custom_vnet = false
  }
}

variable "location" {
  type        = string
  description = "The Azure location where all resources in this example should be created."
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Deploy into this existing resource group; leave empty to create one."
  default     = ""
}