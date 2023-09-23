# locals {
#   #scaleset_worker_name       = "k8s-workers"
#   scaleset_controlplane_name = "k8s-controlplane"
#   token_id                   = format("%s.%s", random_string.token_id.result, random_string.token_secret.result)
#   cluster_name = "freeman"
# }

# # Token for kubeadm
# resource "random_string" "token_id" {
#   length  = 6
#   numeric = true
#   lower   = true
#   special = false
#   upper   = false
# }

# resource "random_string" "token_secret" {
#   length  = 16
#   numeric = true
#   lower   = true
#   special = false
#   upper   = false
# }

# data "azurerm_subscription" "current" {
# }

# /* ------------- NODE IDENTITY ------------- */

# resource "azurerm_user_assigned_identity" "master" {
#   location            = azurerm_resource_group.k8s.location
#   name                = "controlplane"
#   resource_group_name = azurerm_resource_group.k8s.name
# }

# resource "azurerm_role_assignment" "controlplane" {
#   scope                = data.azurerm_subscription.current.id
#   role_definition_name = "Virtual Machine Contributor"
#   principal_id         = azurerm_user_assigned_identity.master.principal_id
# }



# data "azurerm_image" "default" {
#   name = var.image_id
#   resource_group_name = "golden-image-build"
# }

# /* ------------- MASTER ------------- */

# resource "azurerm_public_ip_prefix" "controlplane" {
#   name                = "control-plane-nodes"
#   location            = azurerm_resource_group.k8s.location
#   resource_group_name = azurerm_resource_group.k8s.name

#   prefix_length = 30

#   tags = {
#     environment = "Production"
#   }
# }

# output "ips" {
#   value = azurerm_public_ip_prefix.controlplane
# }


# # resource "azurerm_network_watcher" "main" {
# #   name                = "example-nw"
# #   location            = azurerm_resource_group.k8s.location
# #   resource_group_name = azurerm_resource_group.k8s.name
# # }

# # data "azurerm_network_watcher" "main" {
# #   name = "NetworkWatcher_australiaeast"
# #   resource_group_name = "NetworkWatcherRG"
# # }

# # resource "azurerm_virtual_machine_scale_set_extension" "watcher" {
# #   name                         = "network-watcher"
# #   virtual_machine_scale_set_id = azurerm_linux_virtual_machine_scale_set.controlplane.id
# #   publisher                    = "Microsoft.Azure.NetworkWatcher"
# #   type                         = "NetworkWatcherAgentLinux"
# #   type_handler_version         = "1.4"
# #   auto_upgrade_minor_version   = true
# #   automatic_upgrade_enabled    = true
# # }

# # resource "azurerm_virtual_machine_scale_set_packet_capture" "example" {
# #   name                         = "controlplane"
# #   network_watcher_id           = azurerm_network_watcher.main.id
# #   virtual_machine_scale_set_id = azurerm_linux_virtual_machine_scale_set.controlplane.id

# #   storage_location {
# #     file_path = "/var/captures/packet.cap"
# #   }

# #   machine_scope {
# #     include_instance_ids = ["0"]
# #   }

# #   depends_on = [azurerm_virtual_machine_scale_set_extension.watcher]
# # }

# # resource "azurerm_virtual_machine_scale_set_extension" "monitor" {
# #   name                         = "AzureMonitorLinuxAgent"
# #   virtual_machine_scale_set_id = azurerm_linux_virtual_machine_scale_set.controlplane.id
# #   publisher                    = "Microsoft.Azure.Monitor"
# #   type                         = "AzureMonitorLinuxAgent"
# #   type_handler_version         = "1.25.2"
# #   settings = jsonencode({
# #     "workspaceId": "${azurerm_log_analytics_workspace.law.id}","skipDockerProviderInstall": true
# #   })
# #   protected_settings = jsonencode({
# #     "workspaceKey": "${azurerm_log_analytics_workspace.law.primary_shared_key}"
# #   })
# # }

# # resource "azurerm_virtual_machine_scale_set_extension" "haproxy" {
# #   name                         = "AzureMonitorLinuxAgent"
# #   virtual_machine_scale_set_id = azurerm_linux_virtual_machine_scale_set.controlplane-haproxy.id
# #   publisher                    = "Microsoft.Azure.Monitor"
# #   type                         = "AzureMonitorLinuxAgent"
# #   type_handler_version         = "1.25.1"
# #   settings = jsonencode({
# #     "workspaceId": azurerm_log_analytics_workspace.law.id,"skipDockerProviderInstall": true
# #   })
# #   protected_settings = jsonencode({
# #     "workspaceKey": "${azurerm_log_analytics_workspace.law.primary_shared_key}"
# #   })
# # }


# /* ------------- WORKER ------------- */

# # resource "azurerm_linux_virtual_machine_scale_set" "workers" {
# #   name                = local.scaleset_worker_name
# #   location            = azurerm_resource_group.k8s.location
# #   resource_group_name = azurerm_resource_group.k8s.name
# #   upgrade_mode        = "Manual"
# #   // CHANGEME
# #   sku                 = "Standard_F2"
# #   instances           = 1
# #   admin_username      = "joelfreeman"

# #   admin_ssh_key {
# #     username   = "joelfreeman"
# #     public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDCsTcryUl51Q2VSEHqDRNmceUFo55ZtcIwxl2QITbN1RREti5ml/VTytC0yeBOvnZA4x4CFpdw/lCDPk0yrH9Ei5vVkXmOrExdTlT3qI7YaAzj1tUVlBd4S6LX1F7y6VLActvdHuDDuXZXzCDd/97420jrDfWZqJMlUK/EmCE5ParCeHIRIvmBxcEnGfFIsw8xQZl0HphxWOtJil8qsUWSdMyCiJYYQpMoMliO99X40AUc4/AlsyPyT5ddbKk08YrZ+rKDVHF7o29rh4vi5MmHkVgVQHKiKybWlHq+b71gIAUQk9wrJxD+dqt4igrmDSpIjfjwnd+l5UIn5fJSO5DYV4YT/4hwK7OKmuo7OFHD0WyY5YnkYEMtFgzemnRBdE8ulcT60DQpVgRMXFWHvhyCWy0L6sgj1QWDZlLpvsIvNfHsyhKFMG1frLnMt/nP0+YCcfg+v1JYeCKjeoJxB8DWcRBsjzItY0CGmzP8UYZiYKl/2u+2TgFS5r7NWH11bxoUzjKdaa1NLw+ieA8GlBFfCbfWe6YVB9ggUte4VtYFMZGxOjS2bAiYtfgTKFJv+XqORAwExG6+G2eDxIDyo80/OA9IG7Xv/jwQr7D6KDjDuULFcN/iTxuttoKrHeYz1hf5ZQlBdllwJHYx6fK2g8kha6r2JIQKocvsAXiiONqSfw== hello@world.com"
# #   }

# #   source_image_id = var.image_id

# #   network_interface {
# #     name    = "NetworkProfile"
# #     primary = true

# #     ip_configuration {
# #       name      = "internal"
# #       primary   = true
# #       subnet_id = azurerm_virtual_network.main.subnet["workers"].id
# #     }
# #   }

# #   os_disk {
# #     caching              = "ReadWrite"
# #     storage_account_type = "Premium_LRS"
# #   }

# #   lifecycle {
# #     ignore_changes = ["instances"]
# #   }
# # }
