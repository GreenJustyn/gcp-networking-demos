#Copyright 2025 Google LLC.
#SPDX-License-Identifier: Apache-2.0
variable "regions" { type = list(string) }
variable "vpcs" { }
variable "virtual_machines" { }
variable "apis" { }
variable "project-id-consumer" { type = string }
variable "project-id-producer" { type = string }
variable "append_rand" {
    type = bool
    default = true
}