
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "example" {
  name     = "api-rg-pro"
  location = "West Europe"
}

resource "azurerm_virtual_network" "example" {
  name                = "vnet-network"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "loadip" {
  name                = "TestPublicIp1"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  allocation_method   = "Static"
  sku                 = "Standard"

  depends_on = [
    azurerm_resource_group.example
  ]
}


resource "azurerm_network_security_group" "vijay-nsg" {
  name                = "vijay-nsg"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  
  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "vijay-nsg-rule" {
  name                        = "vijay-nsg-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.example.name
  network_security_group_name = "${azurerm_network_security_group.vijay-nsg.name}"
}

resource "azurerm_subnet_network_security_group_association" "vijay-assocation1" {
  subnet_id                 = azurerm_subnet.internal.id
  network_security_group_id = azurerm_network_security_group.vijay-nsg.id
}


resource "azurerm_lb" "appload" {
  name                = "TestLoadBalancer"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  sku                 = "Standard"
  sku_tier            = "Regional"

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.loadip.id
  }
  depends_on = [
    azurerm_public_ip.loadip
  ]
}


resource "azurerm_lb_backend_address_pool" "scaleset" {
  loadbalancer_id = azurerm_lb.appload.id
  name            = "scaleset"

  depends_on = [
    azurerm_lb.appload
  ]
}

/*
 resource "azurerm_lb_backend_address_pool_address" "appadress" {
  name                    = "example"
  backend_address_pool_id = azurerm_lb_backend_address_pool.backpool.id
  virtual_network_id      = azurerm_virtual_network.example.id  # jo tum virtual machine k liye bnaounge wo
  ip_address              = azurerm_network_interface.appinterface.private_ip_address  # yaha network interface ka refernce dena h jo tum virtual machine k liye bana rahe ho

  depends_on = [
    azurerm_lb_backend_address_pool.backpool,
    azurerm_network_interface.appinterface
  ]
}

*/

resource "azurerm_lb_probe" "probe" {
  loadbalancer_id = azurerm_lb.appload.id
  name            = "probeA"
  port            = 80
  protocol = "Tcp"

  depends_on = [
    azurerm_lb.appload
  ]
}

resource "azurerm_lb_rule" "lbrule" {
  loadbalancer_id                = azurerm_lb.appload.id
  name                           = "LBRuleA"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend-ip"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.scaleset.id]
  probe_id                       = azurerm_lb_probe.probe.id

  depends_on = [
    azurerm_lb.appload
  ]
}

resource "azurerm_linux_virtual_machine_scale_set" "apvijaypset" {
    name = "apvijayv-buntypset"
    resource_group_name = azurerm_resource_group.example.name
    location = azurerm_resource_group.example.location
    sku = "Standard_D2s_v3"
    instances = 2
    admin_username = "adminuser"
    upgrade_mode = "Automatic"

    custom_data = filebase64("customdata.tpl")

     admin_ssh_key {
    username   = "adminuser"
    public_key = file("${path.module}/vijaykey.pub")
  }

    os_disk {
        caching = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }
    source_image_reference {
        publisher = "Canonical"
        offer = "UbuntuServer"
        sku = "16.04-LTS"
        version = "latest"
    }

    network_interface {
    name    = "scale-set-interface"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.internal.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.scaleset.id]
    }
  }


  depends_on = [
    azurerm_subnet.internal,
    azurerm_resource_group.example
  ]
}

