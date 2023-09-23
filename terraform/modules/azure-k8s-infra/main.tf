terraform {
  required_providers {
    null = {
      version = "3.1.1"
      source  = "hashicorp/null"
    }
  }
}

locals {
  prefix = "platformengineering"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "platformengineering" {
  name     = "platformengineering-prod"
  location = "Australia East"
}

resource "azurerm_virtual_network" "platform" {
  name                = "platformengineering-network"
  address_space       = ["10.52.0.0/16"]
  location            = azurerm_resource_group.platformengineering.location
  resource_group_name = azurerm_resource_group.platformengineering.name
}

resource "azurerm_subnet" "k8s" {
  name                 = "platformengineering-aks-sn"
  virtual_network_name = azurerm_virtual_network.platform.name
  resource_group_name  = azurerm_resource_group.platformengineeringname
  address_prefixes     = ["10.52.0.0/24"]
}

resource "random_id" "prefix" {
  byte_length = 8
}

module "aks_cluster_name" {
  source  = "Azure/aks/azurerm"
  version = "7.3.2"

  prefix                               = "pepoc-${random_id.prefix.hex}"
  resource_group_name                  = azurerm_resource_group.platformengineering.name
  admin_username                       = null
  azure_policy_enabled                 = true
  // platformengineering-proof-of-concept
  cluster_name                         = "pepoc-prod"
  disk_encryption_set_id               = azurerm_disk_encryption_set.des.id
  public_network_access_enabled        = false
  identity_ids                         = [azurerm_user_assigned_identity.test.id]
  identity_type                        = "UserAssigned"
  log_analytics_workspace_enabled = false
  maintenance_window = {
    allowed = [
      {
        day   = "Sunday",
        hours = [22, 23]
      },
    ]
    not_allowed = []
  }
  net_profile_pod_cidr              = "10.1.0.0/16"
  private_cluster_enabled           = true
  rbac_aad                          = true
  rbac_aad_managed                  = true
  role_based_access_control_enabled = true

  // KMS etcd encryption
  kms_enabled                  = true
  kms_key_vault_key_id         = azurerm_key_vault_key.kms.id
  kms_key_vault_network_access = "Private"

  depends_on = [
    azurerm_key_vault_access_policy.kms,
    azurerm_role_assignment.kms
  ]
}

