variable "project_hub" {
    type = string
}
variable "project_spoke" {
    type = string
}
variable "regions" {
  type = list(string)
}
variable "apis" {
  type = list(string)
}
variable "append_rand" {
    type = bool
    default = true
}
variable "vpcs" {
  type = list(object({
    delete_default_route: optional(string,false),
    network: string,
    project-id : optional(string),
    auto_create_subnets : optional(bool, false),
    mtu : optional(number,1500)
    subnets : optional(list(object({
      cidr_block : string,
      region : string,
      subnet_name : string
    })))
  }))
}

variable "fw_rules" {
}
variable "vpn_ips" { }

variable "virtual_machines" { }