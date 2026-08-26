#Copyright 2025 Google LLC.
#SPDX-License-Identifier: Apache-2.0
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

variable "machine_size" { type = string }
variable "snapshot_name" { type = string}
variable "snapshot_project" { type = string }
