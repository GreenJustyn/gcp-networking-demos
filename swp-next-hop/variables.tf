#Copyright 2023 Google LLC.
#SPDX-License-Identifier: Apache-2.0
variable "project-id" { type = string }
variable "apis" { type = list(string) }
variable "vpcs" {}
variable "vms" {}
variable "append_rand" {
    type = bool
    default = true
}