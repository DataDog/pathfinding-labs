variable "dev_account_id" {
  description = "The account id of the dev account"
  type        = string
}

variable "prod_account_id" {
  description = "The account id of the prod account"
  type        = string
}

variable "operations_account_id" {
  description = "The account id of the operations account"
  type        = string
}

variable "resource_suffix" {
  description = "Random suffix for globally namespaced resources to prevent conflicts"
  type        = string
} 