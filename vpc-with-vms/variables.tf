variable "project-id" {
    type = string
}
variable "apis" {
  type = list(string)
}
variable "regions" {
    type = list(string)
}
variable "vpcs" {
}

variable "fw_rules" {
}

variable "routes" {
}

variable "psc_ips" { }

variable "append_rand" {
    type = bool
    default = true
}