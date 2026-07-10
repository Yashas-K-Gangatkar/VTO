# VPC module

Provisions a VPC with public and private subnets across multiple AZs, NAT gateways for HA, and a default security group.

## Usage

```hcl
module "vpc" {
  source = "../modules/vpc"

  name_prefix = "vto-staging"
  cidr_block  = "10.1.0.0/16"
  azs         = ["us-east-1a", "us-east-1b", "us-east-1c"]

  tags = {
    Environment = "staging"
    Project     = "vto"
  }
}
```

## Outputs

- `vpc_id`
- `public_subnet_ids` (map: AZ → subnet ID)
- `private_subnet_ids` (map: AZ → subnet ID)
- `default_security_group_id`

## Cost

- 3 NAT Gateways (~$32/month each + data transfer)
- 3 EIPs (free if attached to NAT)
- VPC, subnets, route tables: free

To minimize cost in dev, use a single-AZ configuration.
