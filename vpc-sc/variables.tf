# Common variables
variable "region" {
  type = string
}
variable "apis" {
  type = list(string)
}
# VPC-SC variables
variable "parent_id" {
  description = "The parent of this AccessPolicy in the Cloud Resource Hierarchy. As of now, only organization are accepted as parent."
  type        = string
}
variable "protected_project_ids" {
  description = "Project id and number of the project INSIDE the regular service perimeter. This map variable expects an \"id\" for the project id."
  type        = list(string)
}
variable "unprotected_project_ids" {
  description = "Project id and number of the project outside the service perimeter. This map variable expects an \"id\" for the project id."
  type        = list(string)
}
variable "append_rand" {
    type = bool
    default = true
}
variable "restricted_services" {
  description = "APIs to protect"
  type  = list(string)
}
variable "sa_project_roles" {
  description = "Project IAM Roles for service account created role"
  type = list(string)
}
variable "vpcs" { }
variable "virtual_machines" { }
variable "dns_rp_rules" { }
variable "vms" { }