variable "nameprefix" {
  type = string
}
variable "project-id" {
    type = string
}
variable "region" {
  type = string
}
variable "apis" {
  type = list(string)
}
variable "psc-ip" {
    type = string
}
variable "append_rand" {
    type = bool
    default = true
}
variable "virtual_machines" { }
variable "vpcs" { }
variable "fw_rules" { }