# environments/dev/dns.tf
# Cloud DNS for the app domain + the Google-managed cert's validation records.
#
# When var.dns_zone_name is set we LOOK UP the existing public zone (the zone is
# owned elsewhere, not created here) and manage two records in it:
#   - the DNS-authorization CNAME, so the managed cert can validate -> ACTIVE
#   - an A record pointing the hostname at the load balancer IP

# --- Look up the existing managed zone ---------------------------------------
data "google_dns_managed_zone" "app" {
  count = var.dns_zone_name == "" ? 0 : 1

  name    = var.dns_zone_name                              # zone NAME (e.g. "nativeops-site"), not the dnsName
  project = coalesce(var.dns_zone_project, var.project_id) # owning project
}

# --- DNS-authorization CNAME (so the managed cert validates) ------------------
resource "google_dns_record_set" "cert_auth" {
  for_each = var.dns_zone_name == "" ? {} : module.alb.managed_cert_dns_records

  project      = data.google_dns_managed_zone.app[0].project
  managed_zone = data.google_dns_managed_zone.app[0].name
  name         = each.value.name
  type         = each.value.type # CNAME
  ttl          = 300
  rrdatas      = [each.value.data]
}

# --- A record: hostname -> load balancer -------------------------------------
resource "google_dns_record_set" "app_a" {
  for_each = var.dns_zone_name == "" ? toset([]) : toset(var.managed_cert_domains)

  project      = data.google_dns_managed_zone.app[0].project
  managed_zone = data.google_dns_managed_zone.app[0].name
  name         = "${each.value}."
  type         = "A"
  ttl          = 300
  rrdatas      = [module.alb.load_balancer_ip]
}
