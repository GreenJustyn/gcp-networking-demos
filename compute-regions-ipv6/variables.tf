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