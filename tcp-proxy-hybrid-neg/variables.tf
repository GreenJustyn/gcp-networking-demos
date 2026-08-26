variable "project-id" {
    type = string
}
variable "apis" {
  type = list(string)
}
variable "regions" {
    type = list(string)
}
variable "ip_address_internal1" {
  type = string
}
variable "ip_address_internal2" {
  type = string
}
variable "vpcs" {
}

variable "fw_rules" {
}

variable "routes" {
}

variable "psc_ips" {
}