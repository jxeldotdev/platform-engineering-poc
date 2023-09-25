variable "rg" {
  type = object({
    name     = string
    location = string
  })
}

variable "mandatory" {
  type        = string
  description = "this field is mandatory"
}

variable "optional" {
  default     = "default_value"
  description = "this field is optional"
}
