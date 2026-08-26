variable "project-id" {
    type = string
}
variable "region" {
  type = string
}
variable "apis" {
  type = list(string)
}
variable "append_rand" {
    type = bool
    default = true
}
variable "org-id" {
  type = string
}
variable "vpcs" {
}