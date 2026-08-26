
# Common variables
variable "vpcs" { }
variable "fw_rules" { }
variable "vms" { }
variable "protected_project_ids" {
}
variable "unprotected_project_ids" {
}
variable "vpc_sc_perimeters" {}
variable "region" {
  type = string
}
variable "append_rand" {
    type    = bool
    default = true
}
variable "sa_project_roles" {
  description = "Project IAM Roles for service account created role"
  type = list(string)
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
