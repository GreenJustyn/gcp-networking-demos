
# Common variables
variable "vpcs" { }
variable "fw_rules" { }
variable "virtual_machines" { }
variable "project-ids" {
    #type = string
}
variable "vpc_sc_perimeters" {}
variable "region" {
  type = string
}
variable "append_rand" {
    type    = bool
    default = true
}

variable "apis" {
    type    = list(string)
}

# VPC-SC variables

variable "parent_id" {
  description   = "The parent of this AccessPolicy in the Cloud Resource Hierarchy. As of now, only organization are accepted as parent."
  type          = string
}
variable "protected_apis" {
    type    = list(string)
}
