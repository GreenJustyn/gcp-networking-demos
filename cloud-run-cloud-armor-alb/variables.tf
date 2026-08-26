#Copyright 2023 Google LLC.
#SPDX-License-Identifier: Apache-2.0
variable "region" { type = string }
variable "vpcs" { }
variable "virtual_machines" { }
variable "apis" { }
variable "project-id" { type = string }
variable "append_rand" {
    type = bool
    default = true
}
variable "ip_allow_list" {
  description = "A list of ip addresses that can be white listed through security policies"
}