locals {
  healthcheck_endpoint = "https://${azurerm_app_service.current.default_site_hostname}/api/healthcheck"
}

# Action group to send an email for alerts
resource "azurerm_monitor_action_group" "current" {
  name                = "SendAlertEmail"
  resource_group_name = data.azurerm_resource_group.current.name
  short_name          = "Alert"
  email_receiver {
    name          = "sendtoemail"
    email_address = var.alert_email_address
  }
}

# Availability ping
resource "azurerm_application_insights_web_test" "app_availability" {
  name                    = "availability-${azurerm_app_service.current.name}"
  resource_group_name     = data.azurerm_resource_group.current.name
  location                = data.azurerm_resource_group.current.location
  application_insights_id = azurerm_application_insights.current.id
  kind                    = "ping"
  frequency               = 300
  timeout                 = 60
  enabled                 = true
  geo_locations = [
    "emea-nl-ams-azr",
    "emea-ru-msa-edge",
    "emea-gb-db3-azr",
    "emea-fr-pra-edge",
    "us-va-ash-azr",
  ]
  configuration = <<XML
<WebTest Name="Availability" Id="9a572603-75a7-4754-8f17-74d3a428d7fa" Enabled="True" CssProjectStructure="" CssIteration="" Timeout="120" WorkItemIds="" xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010" Description="" CredentialUserName="" CredentialPassword="" PreAuthenticate="True" Proxy="default" StopOnError="False" RecordedResultFile="" ResultsLocale="">
  <Items>
    <Request Method="GET" Guid="a3e2335b-cee0-ecd3-c892-ca25c94275b4" Version="1.1" Url="${local.healthcheck_endpoint}" ThinkTime="0" Timeout="120" ParseDependentRequests="False" FollowRedirects="True" RecordResult="True" Cache="False" ResponseTimeGoal="0" Encoding="utf-8" ExpectedHttpStatusCode="200" ExpectedResponseUrl="" ReportingName="" IgnoreHttpStatusCode="False" />
  </Items>
</WebTest>
XML
  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

# Availability ping failed alert
resource "azurerm_monitor_metric_alert" "app_availability" {
  name                = "${azurerm_app_service.current.name} server availability"
  resource_group_name = data.azurerm_resource_group.current.name
  # Both the availability web test AND the application insights need to be in the scope
  # https://github.com/terraform-providers/terraform-provider-azurerm/issues/8551
  scopes = [
    azurerm_application_insights_web_test.app_availability.id,
    azurerm_application_insights.current.id,
  ]
  # Every 1 mins in 5 min window
  frequency   = "PT1M"
  window_size = "PT5M"
  # Critical
  severity = 0
  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_web_test.app_availability.id
    component_id          = azurerm_application_insights.current.id
    failed_location_count = 3
  }
  action {
    action_group_id = azurerm_monitor_action_group.current.id
  }
}

# HTTP 5xx errors
resource "azurerm_monitor_metric_alert" "ms_5xx_errors" {
  name                = "${azurerm_app_service.current.name} server had HTTP 5xx errors"
  resource_group_name = data.azurerm_resource_group.current.name
  scopes = [
    azurerm_app_service.current.id,
  ]
  # Every 15 mins in 15 min window
  frequency   = "PT15M"
  window_size = "PT15M"
  # Error
  severity = 1
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }
  action {
    action_group_id = azurerm_monitor_action_group.current.id
  }
}

# Dependency failures (e.g. HTTP request to another service or database query failed)
resource "azurerm_monitor_scheduled_query_rules_alert" "dependency_failures_in_app_service" {
  name                = "${azurerm_app_service.current.name} had dependency failures"
  resource_group_name = data.azurerm_resource_group.current.name
  location            = data.azurerm_resource_group.current.location
  data_source_id      = azurerm_application_insights.current.id
  frequency           = 15
  time_window         = 15
  # Error
  severity = 1
  query    = <<-QUERY
  dependencies
  | where resultCode == "False"
QUERY
  trigger {
    operator  = "GreaterThan"
    threshold = 0
  }
  action {
    action_group = [
      azurerm_monitor_action_group.current.id,
    ]
  }
}

module "vpc4" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.0.0"
  # ARN of Outpost you want to create a subnet in.
  outpost_arn = ""
  # List of maps of egress rules to set on the default security group
  default_security_group_egress = []
  # Assign IPv6 address on database subnet, must be disabled to change IPv6 CIDRs. This is the IPv6 equivalent of map_public_ip_on_launch
  database_subnet_assign_ipv6_address_on_creation = false
  # The ARN of the KMS Key to use when encrypting log data for VPC flow logs.
  flow_log_cloudwatch_log_group_kms_key_id = ""
  # The ARN of the Permissions Boundary for the VPC Flow Log IAM Role
  vpc_flow_log_permissions_boundary = ""
  # Assign IPv6 address on outpost subnet, must be disabled to change IPv6 CIDRs. This is the IPv6 equivalent of map_public_ip_on_launch
  outpost_subnet_assign_ipv6_address_on_creation = false
  # Assign IPv6 address on redshift subnet, must be disabled to change IPv6 CIDRs. This is the IPv6 equivalent of map_public_ip_on_launch
  redshift_subnet_assign_ipv6_address_on_creation = false
  # List of maps of ingress rules to set on the default security group
  default_security_group_ingress = []
  # Assign IPv6 address on elasticache subnet, must be disabled to change IPv6 CIDRs. This is the IPv6 equivalent of map_public_ip_on_launch
  elasticache_subnet_assign_ipv6_address_on_creation = false
  # The Availability Zone for the VPN Gateway
  vpn_gateway_az = ""
  # Assign IPv6 address on private subnet, must be disabled to change IPv6 CIDRs. This is the IPv6 equivalent of map_public_ip_on_launch
  private_subnet_assign_ipv6_address_on_creation = false
  # The fields to include in the flow log record, in the order in which they should appear.
  flow_log_log_format = ""
  # Should be true to enable ClassicLink DNS Support for the VPC. Only valid in regions and accounts that support EC2 Classic.
  enable_classiclink_dns_support = false
  # Should be true to enable ClassicLink for the VPC. Only valid in regions and accounts that support EC2 Classic.
  enable_classiclink = false
  # Specifies the number of days you want to retain log events in the specified log group for VPC flow logs.
  flow_log_cloudwatch_log_group_retention_in_days = 1
  # Assign IPv6 address on intra subnet, must be disabled to change IPv6 CIDRs. This is the IPv6 equivalent of map_public_ip_on_launch
  intra_subnet_assign_ipv6_address_on_creation = false
  # Assign IPv6 address on public subnet, must be disabled to change IPv6 CIDRs. This is the IPv6 equivalent of map_public_ip_on_launch
  public_subnet_assign_ipv6_address_on_creation = false
  # AZ where Outpost is anchored.
  outpost_az = ""
}
