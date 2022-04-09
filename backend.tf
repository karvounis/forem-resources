
terraform {
  backend "s3" {
    endpoint = "https://minio.karvounis.local"
    bucket   = "terraform"
    key      = "forem/terraform.tfstate"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
