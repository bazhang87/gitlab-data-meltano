provider "google" {
    project = "gitlab-analysis"
    region  = "us-west1"
    zone    = "us-west1-a"
}

variable "environment" {
    type = string
}

terraform {
  backend "gcs" {
    bucket  = "gitlab-analysis-data-terraform-state"
    prefix  = "meltano-production/state"
  }
}

resource "google_container_cluster" "meltano_cluster" {
    project = "gitlab-analysis"
    location = "us-west1-a"
    provider = google-beta
    name     = var.environment == "production" ? "data-ops-meltano" : "data-ops-meltano-${var.environment}"
    description = var.environment == "production" ? "Production Meltano cluster" : "${var.environment} Meltano Cluster"
    network = "default"
    remove_default_node_pool = true
    subnetwork="default"
    initial_node_count  = 1
    addons_config {
      horizontal_pod_autoscaling {
        disabled=true
      }
    }
   release_channel {
        channel="UNSPECIFIED"
    }
    notification_config {
        pubsub {
            enabled = false
        }
    }
    vertical_pod_autoscaling {
        enabled=true
    }
    private_cluster_config {
        enable_private_endpoint = false
    }
}

resource "google_container_node_pool" "meltano-pool" {
    name        = var.environment == "production" ? "meltano-pool" : "meltano-pool-${var.environment}"
    location = "us-west1-a"
    cluster     = google_container_cluster.meltano_cluster.name
    node_count = 1
    node_config {
        machine_type    = "e2-standard-4"
        image_type = "COS"
        disk_type = "pd-standard"
        disk_size_gb = 100
        preemptible = false
    }
    upgrade_settings {
      max_surge=1
      max_unavailable=0
    }
    management {
      auto_repair=true
      auto_upgrade=true
    }
}
