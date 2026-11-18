terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.0"
    }
  }
}

# Resource Manager supplies authentication and manages state. No local profile,
# credentials or backend block belong in the uploaded stack.
provider "oci" {
  region = var.region
}
