# variable "vnet" {
#   type = object({
#     name   = string,
#     cidr   = string,
#     ranges = list(string)
#   })
#   default = {
#     name = "k8s-network"
#     cidr = "10.0.0.0/16"
#     ranges = [
#       "10.0.1.0/24",
#       "10.0.2.0/24",
#       "10.0.3.0/24",
#       "10.0.101.0/24",
#       "10.0.102.0/24",
#       "10.0.103.0/24"
#     ]
#   }
# }


variable "location" {
  type    = string
  default = "Australia East"
}

variable "image_id" {
  type    = string
}
