variable "project-id" {
    type = string
    default = null
}

variable "fw_rules" {
  type = list(object({
    id : number,
    priority : number,
    description : optional(string),
    log_config : optional(string),
    network : string,
    name : string,
    direction : optional(string),
    action : optional(string),
    sources : optional(list(string),[]),
    source_list : optional(list(string)),
    target_tags : optional(list(string)),
    rules: optional(list(object({
      ports : optional(list(string))
      protocol : string
    })))
  }))
}

variable "namesuffix" {
    type = string
    default = null
}