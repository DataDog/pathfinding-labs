variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, dev, operations)"
  type        = string
  default     = "prod"
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resources"
  type        = string
}

variable "flag_value" {
  description = "CTF flag value stored in the scenario's flag resource. Populated by plabs from flags.default.yaml (or a vendor override). Defaults to flag{MISSING} so the module is deployable in isolation."
  type        = string
  default     = "flag{MISSING}"
}

variable "bedrock_model_id" {
  description = "Bedrock foundation model ID to supply at CreateHarness time. The model is never invoked during the attack — InvokeAgentRuntimeCommand bypasses the agent loop entirely — but a valid model ID is required by the API."
  type        = string
  default     = "amazon.nova-micro-v1:0"
}
