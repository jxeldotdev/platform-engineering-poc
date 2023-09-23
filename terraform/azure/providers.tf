terraform {
  required_providers {
    # github = {
    #   source  = "integrations/github"
    #   version = "~> 5.0"
    # }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.48.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "2.36.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
  }
  required_version = ">=1.4.0"
}
