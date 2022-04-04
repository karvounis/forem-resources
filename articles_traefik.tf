resource "forem_article" "traefik_standalone_basic" {
  title         = "Basic Traefik configuration tutorial"
  body_markdown = file("${path.module}/files/tutorials/traefik/standalone/basic.md")
  published     = true
  series        = "Traefik configuration tutorials"

  tags = ["traefik", "devops", "docker", "tutorial"]
}
