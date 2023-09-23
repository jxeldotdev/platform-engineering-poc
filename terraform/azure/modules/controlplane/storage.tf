
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "certs" {
  name                        = "cluster-certs"
  location                    = var.rg.location
  resource_group_name         = var.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  enable_rbac_authorization = true
  enabled_for_deployment = true

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get",
    ]

    storage_permissions = [
      "Get",
    ]
    certificate_permissions = [
        "Get",
        "Import"
    ]
  }
}

resource "azurerm_key_vault_access_policy" "master-nodes" {
  key_vault_id = azurerm_key_vault.certs.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.controlplane.principal_id

  key_permissions = [
    "Get", "List", "Encrypt", "Decrypt"
  ]
  certificate_permissions = [
    "Import", "Get", "List", "Recover", "Create"
  ]
}

resource "azurerm_storage_account" "scripts" {
  name                     = "clusterscripts${random_string.lb_suffix.result}"
  resource_group_name      = var.rg.name
  location                 = var.rg.location
  account_tier             = "Standard"
  account_replication_type = "GRS"

  tags = {
    environment = "staging"
  }
}


resource "azurerm_storage_container" "master" {
  name                  = "masters"
  storage_account_name  = azurerm_storage_account.scripts.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "copy_cert_script" {
  name                   = "copy_certs_to_key_vault.py"
  storage_account_name   = azurerm_storage_account.scripts.name
  storage_container_name = azurerm_storage_container.master.name
  type                   = "Block"
  source                 = "${path.module}/bin/copy_certs_to_key_vault.py"
  content_md5            = filemd5("${path.module}/bin/copy_certs_to_key_vault.py")
}