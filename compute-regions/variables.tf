variable "project-id" {
    type = string
}
variable "apis" {
  type = list(string)
}
variable "append_rand" {
    type = bool
    default = true
}
variable "region_filter" {
  type = list(string)
}
variable "vms_per_region" {
  type= string
}
variable "external_ip" {
  type = bool
  default = false
}