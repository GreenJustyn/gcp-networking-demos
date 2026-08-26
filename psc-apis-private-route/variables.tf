variable "nameprefix" {
  type = string
}
variable "project-id" {
    type = string
}
variable "deploy_test_vms" {
  type = bool
}
variable "vm_spec" {
  type = string
}
variable "zoneregions" {
  type    = any
}
variable "subnets" {
  type    = list(string)
}
variable "apis" {
  type = list(string)
}
variable "psc_ips" {
}

variable "dns_rp_rules" {
}