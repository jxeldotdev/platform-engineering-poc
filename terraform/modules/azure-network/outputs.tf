output "vpc" {
  value = azurerm_virtual_network.main
}

output "haproxy_asg" {
  value = azurerm_application_security_group.haproxy.id
}
output "haproxy_subnet" {
  value = data.azurerm_subnet.haproxy.id
}

output "haproxy_nsg" {
  value = azurerm_network_security_group.sgs["haproxy"].id
}

output "controlplane_asg" {
    value = azurerm_application_security_group.controlplane.id
}

output "controlplane_nsg" {
  value = azurerm_network_security_group.sgs["controlplane"].id
}


output "controlplane_subnet" {
  value = data.azurerm_subnet.controlplane.id
}

output "lb_subnet" {
  value = data.azurerm_subnet.lb.id
}