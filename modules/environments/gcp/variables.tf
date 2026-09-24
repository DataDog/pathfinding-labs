terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

variable "environment_name" {
  description = "Name of this environment (prod, dev, ops) — used for resource naming"
  type        = string
}

variable "project_id" {
  description = "GCP project ID this environment deploys into"
  type        = string
}

variable "resource_suffix" {
  description = "Random suffix for globally namespaced resources to prevent conflicts"
  type        = string
}
