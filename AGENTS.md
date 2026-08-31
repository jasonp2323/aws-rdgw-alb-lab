# AGENTS.md

Working notes for anyone — human or agent — changing this repo.

## What this is

A two-account AWS lab in Terraform. Identity (AWS Managed Microsoft AD) lives in
the **network** account; the **workload** account reaches it across a Transit
Gateway shared via RAM, and never hosts a domain controller. It exists to be
destroyed and rebuilt between sessions.

| Account  | ID             | Provider alias / SSO profile |
| -------- | -------------- | ---------------------------- |
| network  | `172106476397` | `aws.network`                |
| workload | `594775506233` | `aws.workload`               |

Region is `us-east-1`. Both accounts are in organization `o-jxhjz490ll`, with
**network as the management account**.

## Hard rules

1. **There is no default provider.** Every resource, data source and module block
   must name `aws.network` or `aws.workload` explicitly. A missing `provider =`
   silently fails at plan time with a confusing error, or worse, resolves
   somewhere you did not intend.
2. **Do not write provider blocks.** `providers.tf` is pre-existing and owned
   outside this work. Do not add `required_providers` entries either — that
   rules out `random`, `tls`, and friends. Anything needing a secret takes a
   `sensitive` variable instead.
3. **Prefer community modules.** `terraform-aws-modules/*` for VPC, Transit
   Gateway, security groups and EC2. Raw resources only where no module exists
   (Managed AD, Resolver endpoints and rules, RAM shares for the resolver rule,
   cross-account attachment acceptance) or where the module cannot express the
   design — both exceptions are commented at the call site.
4. **Tag everything** `Environment=lab`, `Project=identity-isolation`, via
   `local.tags`.
5. **No SSH or RDP inbound, anywhere.** Access is SSM Session Manager only. The
   instance has no key pair and no ingress rules at all. This holds on the
   identity path too: `local.ad_ports` enumerates AD's required ports rather
   than opening the spoke CIDR wholesale.

## File layout

| File                    | Contents                                                                          |
| ----------------------- | --------------------------------------------------------------------------------- |
| `providers.tf`          | Pre-existing. Provider aliases and version pins. **Do not edit.**                  |
| `variables.tf`          | Account IDs, CIDRs, domain, instance sizing, tags                                  |
| `locals.tf`             | Derived subnets/AZs, the spoke registry, the AD port list                          |
| `network-vpc.tf`        | Network VPC: public + private subnets, single NAT gateway                          |
| `network-tgw.tf`        | Transit Gateway, RAM share, both route tables, all association/propagation wiring   |
| `network-ad.tf`         | Managed Microsoft AD, DHCP options, directory sharing, spoke ingress to the AD SG   |
| `network-dns.tf`        | Resolver inbound + outbound endpoints, security groups, forward rule, RAM share     |
| `workload-vpc.tf`       | Workload VPC: private subnets only                                                 |
| `workload-tgw.tf`       | Workload attachment, acceptance in the network account, workload default route      |
| `workload-dns.tf`       | Resolver rule association against the workload VPC                                  |
| `workload-instance.tf`  | Windows Server 2022 instance, its security group, SSM seamless domain join          |
| `outputs.tf`            | IDs worth having after an apply                                                    |

Split is by **account first, concern second**. A new spoke account gets its own
`<spoke>-*.tf` files; it does not get folded into the workload ones.

## Adding a spoke

Designed so this costs no rework:

1. Add a provider alias for the new account (owner's call — see rule 2).
2. Copy `workload-vpc.tf`, `workload-tgw.tf`, `workload-dns.tf` to
   `<spoke>-*.tf` and change the alias, name and CIDR.
3. Add one entry to `local.spoke_cidrs` and one to `local.spoke_attachment_ids`.

That is the whole change. TGW route table associations and propagations, the
directory security group ingress, and the network VPC's routes towards the
spokes all derive from those two maps or from `var.spoke_supernet` (`10.0.0.0/8`),
so no existing routing is touched.

## Things that will bite you

- **`for_each` over route table IDs does not plan.** Route table IDs are unknown
  until apply, and `for_each` keys must be known at plan time. Use `count` with
  `length(...)` (the list length *is* known) or index directly. This is why
  `aws_route.network_*_to_spokes` are two separate resources.
- **`create_tgw_routes = false` still evaluates `ram_name`.** The transit-gateway
  module computes `coalesce(var.ram_name, var.name)` unconditionally, so both
  module instances must set `name` even when they share nothing.
- **A pending TGW attachment rejects route operations.** A cross-account
  attachment sits in `pendingAcceptance` until the owner accepts it. Every route
  table association, propagation and VPC route that touches a spoke attachment
  carries an explicit `depends_on` the accepter. Removing those turns a
  one-pass apply into a two-pass one.
- **The directory's security group only admits the network VPC CIDR.** AWS builds
  it that way. Spoke traffic arriving over the TGW is dropped until
  `aws_vpc_security_group_ingress_rule.ad_from_spokes` opens the AD ports. This
  is not optional — the domain join fails without it.
- **A FORWARD resolver rule requires an *outbound* endpoint**, in the same
  account as the rule. The inbound endpoint cannot serve that role. See the
  comment block at the top of `network-dns.tf` for why the rule targets the
  domain controllers directly rather than the inbound endpoint.
- **The SSM join uses the *shared* directory ID**, not the network account's
  `d-xxxx`. `aws_directory_service_shared_directory.workload.shared_directory_id`
  is the identifier minted in the workload account.
- **Directory creation takes 20-45 minutes.** A full apply is roughly 30-50
  minutes, most of it waiting on Managed AD.

## Checks before you call it done

```bash
terraform fmt -recursive
terraform validate
TF_VAR_directory_admin_password='...' terraform plan
```

`plan` reaches AWS through both SSO profiles, so it catches provider-aliasing
and cross-account mistakes that `validate` cannot.
