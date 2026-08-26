variable "project-id" {
    type = string
}
variable "regions" {
  type = list(string)
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