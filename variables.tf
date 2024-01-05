variable "api_url" {
  description = "URL to the API of Proxmox"
  default     = "https://proxmox.liofal.net:8006/api2/json"
}

variable "target_host" {
  description = "hostname to deploy to"
  default     = "proxmox"
}

variable "token_id" {
  description = "The token created for a user in Proxmox"
  type        = string
  sensitive   = true
  default     = "terraform@pve!terraform"
}

variable "token_secret" {
  description = "The secret created for a user's token in Proxmox"
  type        = string
  sensitive   = true
  default     = "dcac2285-897f-497f-8b82-1dd7eab85aa5"
}