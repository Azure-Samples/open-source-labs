variable "location" {
  type        = string
  default     = "brazilsouth"
  description = "value of Azure region for resource deployment"
}

variable "resource_group_name" {
  type        = string
  description = "Deploy into this existing resource group; leave empty to create one."
  default     = ""
}

variable "vm_size" {
  type        = string
  default     = "Standard_D8s_v4"
  description = "size of the virtual machine"
}

variable "vm_image_offer" {
  type        = string
  default     = "ubuntu-24_04-lts"
  description = "image offer available by the publisher (canonical) - to look up additional offers with `az vm image list-offers -l <your_location> -p canonical --query \"[].name\" -o tsv`"
}

variable "vm_username" {
  type        = string
  default     = "paul"
  description = "username for SSH access"
}