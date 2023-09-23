
variable "admin_user" {
  type = object({
    name = string,
    key = string
  })
}

variable "rg" {
  type = object({
    name = string
    location = string
  })
}

variable "haproxy" {
    type = object({
        subnet_id = string
        nsg_id = string
        asg_id = string
    })
}

variable "controlplane" {
    type = object({
        subnet_id = string
        nsg_id = string
        asg_id = string
    })
}

variable "lb_subnet" {
  type = string
}