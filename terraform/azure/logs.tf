resource "azurerm_log_analytics_workspace" "law" {
  resource_group_name = azurerm_resource_group.k8s.name
  location            = azurerm_resource_group.k8s.location
  name                = "node-logs"
}

resource "azurerm_log_analytics_solution" "vminsights" {
  resource_group_name   = azurerm_resource_group.k8s.name
  location              = azurerm_resource_group.k8s.location
  solution_name         = "VMInsights"

  workspace_resource_id = azurerm_log_analytics_workspace.law.id
  workspace_name        = azurerm_log_analytics_workspace.law.name

  plan {
    product = "OMSGallery/VMInsights"
    publisher = "Microsoft"
  }
}
