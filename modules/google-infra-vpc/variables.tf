
variable "project-id" {
    type = string
    default = null
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
      subnet_name : string,
      purpose : optional(string, null),
      role : optional(string, null),
      pga : optional(string, null)
    })))
  }))
}

variable "namesuffix" {
    default = null
    type = string
}
