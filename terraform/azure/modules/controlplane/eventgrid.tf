

# resource "azurerm_app_service_plan" "example" {
#   name                = "misc"
#   location            = var.rg.location
#   resource_group_name = var.rg.name
#   kind                = "elastic"

#   sku {
#     tier = "WorkflowStandard"
#     size = "WS1"
#   }
# }

# // storageaccount for function, required
# resource "azurerm_storage_account" "function" {
#   name                      = "${random_string.lb_suffix.result}function"
#   resource_group_name       = var.rg.name
#   location                  = var.rg.location
#   account_tier              = "Standard"
#   account_replication_type  = "LRS"
#   account_kind              = "StorageV2"
#   enable_https_traffic_only = true
#   tags = {
#     sample = "azure-functions-event-grid-terraform"
#   }
# }

# // storageaccount to store event grid data
# resource "azurerm_storage_account" "eventgrid" {
#   name                      = "${var.prefix}eventgrid"
#   resource_group_name       = var.rg.name
#   location                  = var.rg.location
#   account_tier              = "Standard"
#   account_replication_type  = "LRS"
#   account_kind              = "StorageV2"
#   enable_https_traffic_only = true
#   tags = {
#     sample = "azure-functions-event-grid-terraform"
#   }
# }

# resource "azurerm_eventgrid_topic" "sample_topic" {
#   name                = "${var.prefix}-azsam-egt"
#   location            = var.rg.location
#   resource_group_name = var.rg.name
#   tags = {
#     sample = "azure-functions-event-grid-terraform"
#   }
# }


# resource "azurerm_eventgrid_event_subscription" "eventgrid_subscription" {
#   name   = "${var.prefix}-handlerfxn-egsub"
#   scope  = azurerm_linux_virtual_machine_scale_set.controlplane.id
#   labels = ["azure-functions-event-grid-terraform"]
#   azure_function_endpoint {
#     function_id = "${module.functions.function_id}/functions/${var.eventGridFunctionName}"

#     # defaults, specified to avoid "no-op" changes when 'apply' is re-ran
#     max_events_per_batch              = 1
#     preferred_batch_size_in_kilobytes = 64
#   }
# }

# resource "azurerm_linux_function_app" "example" {
#   name                = "example-linux-function-app"
#   resource_group_name = var.rg.name
#   location            = var.rg.location

#   storage_account_name       = azurerm_storage_account.function.name
#   storage_account_access_key = azurerm_storage_account.function.primary_access_key
#   service_plan_id            = azurerm_service_plan.example.id

#   site_config {}

#   application_stack {
#     python_version = "3.10"
#   }
# }

# resource "azurerm_function_app_function" "example" {
#   name            = "example-function-app-function"
#   function_app_id = azurerm_linux_function_app.example.id
#   language        = "Python"
#   file {
#     name = "main.py"
#     content = file("${path.module}/bin/function/gen_join_cmd.py")
#   }
#   test_data = jsonencode({
#     "name" = "Azure"
#   })
#   config_json = jsonencode({
#     "bindings" = [
#       {
#         "authLevel" = "function"
#         "direction" = "in"
#         "methods" = [
#           "get",
#           "post",
#         ]
#         "name" = "req"
#         "type" = "httpTrigger"
#       },
#       {
#         "direction" = "out"
#         "name"      = "$return"
#         "type"      = "http"
#       },
#     ]
#   })
# }

# resource "azurerm_logic_app_standard" "example" {
#   name                       = "generate-join-command"
#   location                   = var.rg.location
#   resource_group_name        = var.rg.name
#   app_service_plan_id        = azurerm_app_service_plan.example.id
#   storage_account_name       = azurerm_storage_account.function.name
#   storage_account_access_key = azurerm_storage_account.function .primary_access_key

#   app_settings = {
#     "FUNCTIONS_WORKER_RUNTIME"     = "python"
#   }
# }