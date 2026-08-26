#Copyright 2023 Google LLC.
#SPDX-License-Identifier: Apache-2.0
variable "project-id" { type = string }
variable "region" { type = string }
variable "regions" { }
variable "cr_base_asn" { type = string }
variable "vpcs" { }
variable "virtual_machines" { }
variable "apis" { type = list(string) }
variable "peerings" { }
variable "append_rand" {
    type = bool
    default = true
}
variable "vpn_ips" { }