# -----------------------------------------------------------------------
# FinOps Demo App 005 — Redundant / Expensive Resources (Terraform)
# -----------------------------------------------------------------------
# Terraform equivalent of main.bicep for Infracost cost analysis.
# INTENTIONALLY deploys redundant and expensive Azure resources:
#   - 2 duplicate S3 App Service Plans in non-approved regions (~$200/month each)
#   - GRS storage where LRS would suffice (~$50/month vs ~$2/month)
#   - Web apps on each plan, duplicating workload across regions
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
  default     = "eastus"
  description = "Primary resource location (used for storage only)"
}

variable "resource_group_name" {
  default     = "rg-finops-demo-005"
  description = "Resource group name"
}

locals {
  common_tags = {
    Environment = "Development"
    Application = "finops-demo-005"
    CostCenter  = "CC-1234"
    Owner       = "team@contoso.com"
    Department  = "Engineering"
    Project     = "FinOps-Scanner"
    ManagedBy   = "Terraform"
  }
}

# INTENTIONAL-FINOPS-ISSUE: S3 App Service Plan in westeurope — non-approved region (~$200/month)
# Approved regions are: eastus, eastus2, centralus
resource "azurerm_service_plan" "europe" {
  name                = "asp-finops-demo-005-eu"
  location            = "westeurope"
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "S3"
  tags                = local.common_tags
}

# INTENTIONAL-FINOPS-ISSUE: S3 App Service Plan in southeastasia — non-approved region (~$200/month)
# Duplicate of Europe plan, doubling costs for the same workload
resource "azurerm_service_plan" "asia" {
  name                = "asp-finops-demo-005-sea"
  location            = "southeastasia"
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "S3"
  tags                = local.common_tags
}

resource "azurerm_linux_web_app" "europe" {
  name                = "app-finops-demo-005-eu"
  location            = "westeurope"
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.europe.id
  https_only          = true

  site_config {
    minimum_tls_version = "1.2"
  }

  tags = local.common_tags
}

resource "azurerm_linux_web_app" "asia" {
  name                = "app-finops-demo-005-sea"
  location            = "southeastasia"
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.asia.id
  https_only          = true

  site_config {
    minimum_tls_version = "1.2"
  }

  tags = local.common_tags
}

# INTENTIONAL-FINOPS-ISSUE: GRS storage where LRS would suffice (~$50/month vs ~$2/month)
# Development workloads do not require geo-redundant storage
resource "azurerm_storage_account" "grs" {
  name                     = "stfinops005tf"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "GRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"
  tags                     = local.common_tags
}
