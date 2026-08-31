# Identity isolation lab

A two-account AWS lab in Terraform. **Identity lives in the network account and
the workload account never hosts a domain controller.** A Windows instance in
the workload account joins `corp.theuptimestudio.co` across a Transit Gateway,
using a directory it does not own, over a path with no SSH or RDP anywhere in it.

| Account  | ID             | Provider alias | Holds                                                   |
| -------- | -------------- | -------------- | ------------------------------------------------------- |
| network  | `172106476397` | `aws.network`  | Managed Microsoft AD, TGW, NAT egress, Resolver endpoints |
| workload | `594775506233` | `aws.workload` | Private VPC and one domain-joined Windows instance        |

Region `us-east-1`. Both accounts sit in organization `o-jxhjz490ll`, network
being the management account.

## High level

```mermaid
flowchart LR
    subgraph NET["network account · 172106476397"]
        direction TB
        AD["AWS Managed Microsoft AD<br/>corp.theuptimestudio.co<br/><i>Standard, 2 AZs</i>"]
        NAT["NAT gateway<br/><i>egress for every account</i>"]
        R53["Route 53 Resolver<br/>inbound + outbound endpoints"]
    end

    subgraph TGW["Transit Gateway · shared via RAM"]
        direction TB
        RTS["<b>shared</b> route table<br/>sees all attachments"]
        RTP["<b>spoke</b> route table<br/>sees only the network VPC<br/>+ default route out"]
    end

    subgraph WL["workload account · 594775506233"]
        direction TB
        WIN["Windows Server 2022<br/><i>domain joined via SSM</i>"]
    end

    NET <--> RTS
    RTP <--> WL
    RTS -.->|"propagated"| RTP

    WIN -.->|"① DNS for corp.*"| R53
    WIN -.->|"② Kerberos / LDAP / SMB"| AD
    WIN -.->|"③ internet egress"| NAT

    SPOKE2["future spoke"]:::ghost
    SPOKE2 -.-> RTP

    classDef ghost stroke-dasharray: 4 4,opacity:0.55
```

The **spoke** route table is the isolation boundary. It carries a route to the
network VPC and a default route for egress, and nothing else — so a second spoke
added tomorrow can reach identity and the internet, but not this one.

## Detail

```mermaid
flowchart TB
    subgraph NETACC["network account · 10.20.0.0/16"]
        IGW(["Internet gateway"])

        subgraph NPUB["public subnets · 10.20.32.0/20, 10.20.48.0/20"]
            NATGW["NAT gateway<br/><i>single</i>"]
        end

        subgraph NPRIV["private subnets · 10.20.0.0/20, 10.20.16.0/20"]
            DC["Domain controllers<br/>ENIs + directory SG"]
            EPIN["Resolver <b>inbound</b><br/>endpoint"]
            EPOUT["Resolver <b>outbound</b><br/>endpoint"]
            ATTN["TGW attachment"]
        end

        RTPUB["public route table<br/>0.0.0.0/0 → IGW<br/>10.0.0.0/8 → TGW"]
        RTPRIV["private route table<br/>0.0.0.0/0 → NAT<br/>10.0.0.0/8 → TGW"]
        DHCP["DHCP option set<br/>DNS → domain controllers"]
    end

    subgraph HUB["Transit Gateway"]
        SHARED["<b>shared</b> RT<br/>← network attachment associated<br/>← all attachments propagate"]
        SPOKE["<b>spoke</b> RT<br/>← spoke attachments associated<br/>10.20.0.0/16 propagated<br/>0.0.0.0/0 → network attachment"]
    end

    subgraph WLACC["workload account · 10.30.0.0/16"]
        subgraph WPRIV["private subnets only · 10.30.0.0/20, 10.30.16.0/20"]
            EC2["Windows Server 2022<br/>no key pair · no ingress"]
            ATTW["TGW attachment<br/><i>accepted in network account</i>"]
        end
        RTW["private route tables<br/>0.0.0.0/0 → TGW"]
    end

    NATGW --> IGW
    RTPUB -.- NPUB
    RTPRIV -.- NPRIV
    DHCP -.- NPRIV

    ATTN === SHARED
    ATTN -.->|propagates| SPOKE
    ATTW === SPOKE
    ATTW -.->|propagates| SHARED

    RTW -.- WPRIV
    EC2 --> RTW
    RTPRIV --> NATGW

    EPOUT -->|"forward corp.* :53"| DC
    EPIN -->|"resolves via VPC resolver<br/>+ the same rule"| EPOUT

    RAM1{{"RAM: Transit Gateway"}}
    RAM2{{"RAM: Resolver rule"}}
    DS{{"Directory sharing<br/>HANDSHAKE + accepter"}}

    HUB -.- RAM1 -.-> WLACC
    NETACC -.- RAM2 -.-> WLACC
    NETACC -.- DS -.-> WLACC
```

### How the workload instance resolves `corp.theuptimestudio.co`

1. The instance asks the Amazon resolver at `10.30.0.2` — the workload VPC keeps
   the default DNS server, with no DHCP option set of its own.
2. A Route 53 Resolver **forwarding rule**, created in the network account,
   shared via RAM and associated with the workload VPC, matches the AD zone.
3. The query passes through the **outbound endpoint** named on that rule, in the
   network VPC, and is forwarded to the domain controllers' DNS IPs.
4. Everything else resolves normally through the Amazon resolver.

**One deviation from the original brief, deliberate.** The brief called for the
rule to forward to the *inbound endpoint* IPs. That does not resolve anything on
its own: an inbound endpoint answers out of the network VPC's resolver, which
knows nothing about the AD zone until this very rule is associated with that VPC
— at which point the rule points at itself and loops. The rule targets the domain
controllers directly instead, which is the hop that actually resolves. The
inbound endpoint is still built, doing the job an inbound endpoint is for:
serving as the DNS ingress point for anything outside the VPC, and it now
answers correctly for the AD zone because the same rule is associated with the
network VPC.

### How it joins the domain

`AWS-JoinDirectoryServiceDomain`, driven by an `aws_ssm_association`, pointed at
the **shared directory ID** — the identifier minted in the workload account when
the network account shared the directory. Cross-account seamless join is not
possible without that share.

## Getting started

```bash
cp terraform.tfvars.example terraform.tfvars   # then set a real password
terraform init
terraform plan
terraform apply
```

A full apply runs roughly 30–50 minutes; most of that is Managed AD creating
domain controllers.

### Prerequisite, once per organization

```bash
aws ram enable-sharing-with-aws-organizations --profile network
```

Without it, RAM treats the workload account as external, invitations go
unaccepted, and the TGW attachment fails. It is an organization-level setting,
so it survives `terraform destroy` and only needs running once.

### Verifying

```bash
terraform output session_manager_command    # prints the ssm start-session line
```

Then on the instance:

```powershell
nltest /dsgetdc:corp.theuptimestudio.co     # a domain controller answers
Resolve-DnsName corp.theuptimestudio.co     # returns the DC private IPs
(Get-WmiObject Win32_ComputerSystem).Domain # corp.theuptimestudio.co
```

## Tearing down

```bash
terraform destroy
```

Directory sharing and the TGW attachment unwind in the right order on their own.
Expect the directory itself to take a while.

## Design notes

Layout, conventions, and the traps worth knowing before editing are in
**[AGENTS.md](AGENTS.md)**.
