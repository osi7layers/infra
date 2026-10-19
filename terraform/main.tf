module "network" {
  source = "./modules/network"

  project             = var.project
  vpc_cidr            = var.vpc_cidr
  azs                 = var.azs
  public_subnet_cidrs = var.public_subnet_cidrs
  app_subnet_cidrs    = var.app_subnet_cidrs
  nat_gateway_count   = var.nat_gateway_count
}

module "security" {
  source = "./modules/security"

  project                = var.project
  vpc_id                 = module.network.vpc_id
  node_service_port_from = var.node_service_port_from
  node_service_port_to   = var.node_service_port_to
}

module "ecr" {
  source = "./modules/ecr"

  project              = var.project
  namespace            = var.ecr_namespace
  repositories         = var.ecr_repositories
  image_tag_mutability = var.ecr_image_tag_mutability
  keep_image_count     = var.ecr_keep_image_count
  force_delete         = var.ecr_force_delete
}

module "iam" {
  source = "./modules/iam"

  project             = var.project
  ecr_pull_policy_arn = module.ecr.pull_policy_arn
}

module "eks" {
  source = "./modules/eks"

  project             = var.project
  cluster_name        = "${var.project}-eks"
  kubernetes_version  = var.eks_kubernetes_version
  service_ipv4_cidr   = var.eks_service_cidr
  subnet_ids          = module.network.app_subnet_ids
  cluster_role_arn    = module.iam.eks_cluster_role_arn
  node_role_arn       = module.iam.node_role_arn
  node_sg_id          = module.security.node_sg_id
  public_access_cidrs = var.eks_public_access_cidrs
  node_instance_types = var.eks_node_instance_types
  node_desired_size   = var.eks_node_desired_size
  node_min_size       = var.eks_node_min_size
  node_max_size       = var.eks_node_max_size
  access_entries      = var.eks_access_entries
}
