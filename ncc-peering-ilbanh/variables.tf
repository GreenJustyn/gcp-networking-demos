#Copyright 2023 Google LLC.
#SPDX-License-Identifier: Apache-2.0
variable "project-id" { type = string }
variable "region" { type = string }
variable "vpcs" { }
variable "fw_rules" { }
variable "virtual_machines" { }
variable "apis" { type = list(string) }