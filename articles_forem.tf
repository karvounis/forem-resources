resource "forem_article" "forem_terraform_provider_introduction" {
  title         = "Introducing a Terraform provider for Forem"
  body_markdown = file("${path.module}/files/forem/terraform_provider_intro.md")
  published     = false

  tags = ["announcement", "forem", "automation", "terraform"]
}
