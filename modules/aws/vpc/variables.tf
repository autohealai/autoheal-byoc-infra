# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "vpc_cidr" {
  type        = string
  default     = "10.60.0.0/16"
  description = "CIDR block for the VPC."
}

variable "availability_zones" {
  type        = list(string)
  description = "AZs to spread subnets across (one public + one private per AZ). Two or three recommended."
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name used for the kubernetes.io/cluster/<name> subnet discovery tags. Pass the same id the eks module uses (<namespace>-<environment>-<name>)."
}
