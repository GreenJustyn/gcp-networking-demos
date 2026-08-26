variable "project-id" {
    type = string
}
variable "region-1" {
  type = string
}
variable "apis" {
  type = list(string)
}
variable "append_rand" {
    type = bool
    default = true
}
variable "vpcs" {
}

variable "fw_rules" {
}