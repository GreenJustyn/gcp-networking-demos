#Copyright 2025 Google LLC.
#SPDX-License-Identifier: Apache-2.0
variable "vpcs" { }
variable "virtual_machines" { }
variable "apis" { }
variable "project-id" { type = string }
variable "append_rand" {
    type = bool
    default = true
}

variable "all_zones" {
    type = bool
    default = true
}

variable "regions" {
    type = list(string)
}