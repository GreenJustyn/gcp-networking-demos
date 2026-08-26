#Copyright 2024 Google LLC.
#SPDX-License-Identifier: Apache-2.0
variable "region" { type = string }
variable "vpcs" { }
variable "fw_rules" { }
variable "virtual_machines" { }
variable "apis" { }
variable "project-id-consumer" { type = string }
variable "project-id-producer" { type = string }
variable "append_rand" {
    type = bool
    default = true
}
