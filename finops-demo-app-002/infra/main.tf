# -----------------------------------------------------------------------
# FinOps Demo App 002 — Oversized Resources (Terraform)
# -----------------------------------------------------------------------
# Terraform equivalent of main.bicep for Infracost cost analysis.
# INTENTIONALLY deploys oversized Azure resources for a dev workload:
#   - P3v3 App Service Plan (~$700/month) where B1 ($13/month) suffices
#   - Premium_LRS Storage (~$100/month) where Standard_LRS ($2/month) suffices
# -----------------------------------------------------------------------

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  default     = "canadacentral"
  description = "Azure region for all resources"
}

variable "resource_group_name" {
  default     = "rg-finops-demo-002"
  description = "Resource group name"
}

locals {
  common_tags = {
    Environment = "Development"
    Application = "finops-demo-002"
    CostCenter  = "CC-1234"
    Owner       = "team@contoso.com"
    Department  = "Engineering"
    Project     = "FinOps-Scanner"
    ManagedBy   = "Terraform"
  }
}

# INTENTIONAL-FINOPS-ISSUE: P3v3 plan is massively oversized for a dev static site (~$700/month)
# A B1 plan ($13/month) is the maximum allowed SKU for dev environments
resource "azurerm_service_plan" "oversized" {
  name                = "asp-finops-demo-002"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "P3v3"
  tags                = local.common_tags
}

resource "azurerm_linux_web_app" "app" {
  name                = "app-finops-demo-002"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.oversized.id
  https_only          = true

  site_config {
    minimum_tls_version = "1.2"
  }

  tags = local.common_tags
}

# INTENTIONAL-FINOPS-ISSUE: Premium_LRS storage for a static site dev workload (~$100/month)
# Standard_LRS ($2/month) is the maximum allowed tier for dev environments
resource "azurerm_storage_account" "premium" {
  name                     = "stfinops002tf"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Premium"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"
  tags                     = local.common_tags
}
