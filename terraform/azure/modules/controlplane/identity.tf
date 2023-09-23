resource "azurerm_user_assigned_identity" "controlplane" {
  location            = var.rg.location
  name                = "controlplane"
  resource_group_name = var.rg.name
}

resource "azurerm_role_assignment" "controlplane-contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_user_assigned_identity.controlplane.principal_id
}

resource "azurerm_role_assignment" "controlplane-blob" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.controlplane.principal_id
}

resource "azurerm_role_assignment" "controlplane-kv" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_user_assigned_identity.controlplane.principal_id
}

resource "azurerm_user_assigned_identity" "haproxy" {
  location            = var.rg.location
  name                = "haproxy"
  resource_group_name = var.rg.name
}

resource "azurerm_role_assignment" "haproxy-contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_user_assigned_identity.haproxy.principal_id
}
