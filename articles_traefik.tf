locals {
  traefik_tutorial_tags   = ["traefik", "devops", "docker", "tutorial"]
  traefik_tutorial_series = "Traefik configuration tutorials"
}

resource "forem_article" "traefik_standalone_basic" {
  title         = "Basic Traefik configuration tutorial"
  body_markdown = file("${path.module}/files/tutorials/traefik/standalone/basic.md")
  published     = true
  series        = local.traefik_tutorial_series

  tags = local.traefik_tutorial_tags
}

resource "forem_article" "traefik_standalone_advanced" {
  title         = "Advanced Traefik configuration tutorial - TLS, dashboard, ping, metrics, authentication and more"
  body_markdown = file("${path.module}/files/tutorials/traefik/standalone/advanced.md")
  published     = true
  series        = local.traefik_tutorial_series

  tags = local.traefik_tutorial_tags
}
