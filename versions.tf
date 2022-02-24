terraform {
  required_version = ">= 1.0.0"

  required_providers {
    template = {
      source  = "gxben/template"
      # version has to be set explicitly instead of using a > sign
      version = "= 2.2.0-m1"
    }
  }
}
