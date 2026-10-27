# VPS vs Fly for the voice workers, and LiveKit Cloud vs self-hosted (#344)

Research for #344: what the voice workers and the LiveKit media server would cost
on São Paulo VPS or dedicated servers instead of Fly `gru` and LiveKit Cloud, at
**200 concurrent 10-minute 1:1 audio sessions**. Prices were read on **2026-10-26**
from the official pages or the providers' public, unauthenticated catalogue APIs
linked next to each figure. No account was created and nothing was deployed.
Everything marked **unverified** needs a check before a decision depends on it.

Inputs from earlier research:

- [`voice-worker-capacity.md`](voice-worker-capacity.md) (#401): an idle worker takes
  2,920 MB, each session **360 MB** and **6.4 % of one M3 core**; the worker stops
  taking jobs at a CPU load of 0.7.
- [`production-infrastructure.md`](production-infrastructure.md): LiveKit Cloud plans,
  Phoenix on Fly performance-1x in `gru` (about $53/month), Neon in `aws-sa-east-1`.
- [`../operations/deploy.md`](../operations/deploy.md) and #404: the Phoenix drain,
  Fly `bluegreen` and `fly-replay` design.

## Result

Monthly USD at 200 concurrent sessions. Neon, LLM, Deepgram and Cartesia are left out:
they are the same in every option. Two monthly volumes, because LiveKit Cloud bills
minutes and the compute bills capacity: **20k** stations/month (the example volume of
`production-infrastructure.md`) and **100k** (200 concurrent for about 2.8 hours a day).

| Option | Workers (today, 360 MB/session) | Workers (threads, 4× less memory) | 20k stations | 100k stations | 100k, threads |
|---|---|---|---|---|---|
| (a) All Fly + LiveKit Cloud (current plan) | 11 × Fly perf-4x 12 GB = 2,772 | 11 × Fly perf-4x 8 GB = 2,345 | **3,018** | **3,615** | 3,188 |
| (b) Phoenix on Fly, workers on VPS, LiveKit Cloud | 7 × Vultr 8 vCPU/16 GB dedicated = 1,120 | 11 × Vultr 4 vCPU/8 GB dedicated = 880 | **1,348** | **1,873** | 1,633 |
| (c) As (b), LiveKit self-hosted on a VPS (one node) | 1,120 | 880 | **1,263** | **1,263** | 1,023 |
| (d) Everything on VPS (Phoenix, workers, LiveKit) | 1,120 | 880 | **1,280** | **1,280** | 1,040 |

How the totals add up is in [Totals per option](#totals-per-option).

**Recommendation: (b) for the launch, (c) later.** Moving only the workers to a São Paulo
VPS cuts about **$1,670 to $1,740 a month** at either volume. It changes nothing in Phoenix,
the drain or `fly-replay`. The worker has no inbound service and no Fly-specific code, and a
VPS lets the worker finish its jobs on `SIGTERM` for longer than Fly's 300 s. Self-hosting
LiveKit saves another $85 to $610 a month, but it brings back TURN, TLS and a single point
of failure for every room. Do that after the launch, once the volume is above about 30k
stations/month and TURN has been tested from hospital and university networks. (d) saves
nothing over (c) and means rewriting the #404 drain and replay design. Not worth it.

## 1. VPS and dedicated servers in São Paulo

The worker needs about **4 vCPU with 8–12 GB** for about 20 sessions today, or **8 vCPU with
16–32 GB** for about 40. Realtime audio needs **dedicated** vCPUs: shared plans are listed
for reference only.

### Who has a São Paulo datacenter

| Provider | São Paulo | Source |
|---|---|---|
| Vultr | Yes, region `sao` | <https://api.vultr.com/v2/regions> |
| Akamai (Linode) | Yes, region `br-gru` | <https://api.linode.com/v4/regions> |
| AWS Lightsail | Yes, `sa-east-1` (half the transfer allowance) | <https://aws.amazon.com/lightsail/pricing/> |
| Locaweb | Servers "in Brazil"; city **unverified** | <https://www.locaweb.com.br/servidor-vps/> |
| Magalu Cloud | Yes, `br-se1` (Greater São Paulo); prices **unverified** (see below) | <https://magalu.cloud/precos/> |
| DigitalOcean | **No**: 16 datacenters, none in Brazil | <https://docs.digitalocean.com/platform/regional-availability/> |
| Hetzner | **No**: Germany, Finland, USA, Singapore | <https://docs.hetzner.com/cloud/general/locations/> |
| OVHcloud | **No**: its Brazil pages serve Brazilian customers from American datacentres | <https://www.ovhcloud.com/en/bare-metal/dedicated-server-brazil/> |
| Equinix Metal | **Closed** on 2026-06-30 | <https://docs.equinix.com/releases/end-of-life/eol-products-services> |
| Contabo | No Brazil location found (**unverified**) | <https://contabo.com/en-us/vps/> |

Magalu Cloud's price calculator loads its data in the browser from
`https://api.magalu.cloud/sku/v0/skus?region=br-se1`. That address answered `404` outside
the browser, so no Magalu price is given here. It bills in BRL, which is the reason to check
it by hand.

### Prices

Monthly USD, IPv4 included unless noted. "Transfer" is the outbound allowance included in
the price.

**Vultr `sao`.** Source: the public plan catalogues <https://api.vultr.com/v2/plans> and
<https://api.vultr.com/v2/plans-metal> (2026-10-26). `voc-*` (Optimized Cloud) and bare
metal have dedicated CPUs. `vhp`/`vc2` are shared.

| Plan | vCPU | RAM | $/month | Transfer | CPU |
|---|---|---|---|---|---|
| `voc-c-4c-8gb-75s-amd` (CPU optimized) | 4 | 8 GB | 80 | 6 TB | dedicated |
| `voc-g-4c-16gb-80s-amd` (general purpose) | 4 | 16 GB | 120 | 6 TB | dedicated |
| `voc-c-8c-16gb-150s-amd` (CPU optimized) | 8 | 16 GB | 160 | 7 TB | dedicated |
| `voc-g-8c-32gb-160s-amd` (general purpose) | 8 | 32 GB | 240 | 7 TB | dedicated |
| `voc-m-8c-64gb-400s-amd` (memory optimized) | 8 | 64 GB | 320 | 9 TB | dedicated |
| `vbm-6c-32gb` bare metal, Xeon E-2286G | 6 cores / 12 threads | 32 GB | 185 | 5 TB | whole server |
| `vbm-8c-64gb-amd` bare metal, EPYC 4345P | 8 cores / 16 threads | 64 GB | 365 | 10 TB | whole server |
| `vhp-4c-12gb` (High Performance, shared) | 4 | 12 GB | 72 | 7 TB | shared |
| `vhp-8c-16gb` (High Performance, shared) | 8 | 16 GB | 96 | 8 TB | shared |

- Egress above the allowance: **$0.01/GB**, outbound only
  (<https://docs.vultr.com/support/platform/billing/what-is-the-bandwidth-overage-rate>).
  A 2023 post adds 2 TB of free account-wide egress and pooled allowances
  (<https://blogs.vultr.com/Vultr-Announces-Reduced-Bandwidth-Pricing-2-Tb-Of-Free-Monthly-Egress-Free-Ingress-And-Global-Pooling>). Whether that still holds is **unverified**.
- DDoS protection: **$10/month per instance**, 10 Gbps, layers 3–4
  (<https://docs.vultr.com/support/platform/billing/how-much-does-ddos-protection-cost>).
- SLA: the site advertises "100% SLA". The credit terms were not read (**unverified**).

**Akamai (Linode) `br-gru`.** Source: <https://api.linode.com/v4/linode/types> (the
`region_prices` entry for `br-gru`, 40 % above the base price) and
<https://api.linode.com/v4/network-transfer/prices> (2026-10-26).

| Plan | vCPU | RAM | $/month in `br-gru` | Transfer |
|---|---|---|---|---|
| `g6-dedicated-4` | 4 | 8 GB | 100.80 | 5 TB |
| `g6-dedicated-8` | 8 | 16 GB | 201.60 | 6 TB |
| `g6-dedicated-16` | 16 | 32 GB | 403.20 | 7 TB |
| `g7-premium-8` (dedicated, newer CPU) | 8 | 16 GB | 241.92 | 6 TB |
| `g6-standard-8` (shared) | 8 | 32 GB | 268.80 | 16 TB |

- Egress above the pooled allowance: **$0.007/GB** in `br-gru` (base $0.005).
- The G8 dedicated plans list no `br-gru` price, so they are probably not offered there (**unverified**).
- SLA **99.99 %** with service credits (<https://www.akamai.com/legal/sla-compute>, v1.2 of
  2026-02-27). DDoS protection is listed as included with Compute
  (<https://www.akamai.com/site/en/documents/corporate/akamai-services-descriptions.pdf>).

**AWS Lightsail `sa-east-1`.** Source: <https://aws.amazon.com/lightsail/pricing/>. The page
lists one price for every region. São Paulo gets **half** the listed transfer.

| Bundle | vCPU | RAM | $/month (IPv4) | Transfer in São Paulo |
|---|---|---|---|---|
| Compute Optimized 8 GB | 4 | 8 GB | 84 | 3 TB |
| Compute Optimized 16 GB | 8 | 16 GB | 168 | 3.5 TB |
| Compute Optimized 32 GB | 16 | 32 GB | 336 | 4 TB |
| Memory Optimized 32 GB | 4 | 32 GB | 144 | 3 TB |
| General Purpose 16 GB | 4 | 16 GB | 84 | 3 TB |

- Without IPv4 the price is $4/month lower.
- The overage rate "varies by AWS Region". The page gives only Ohio's $0.09/GB, so the
  São Paulo rate is **unverified**.
- Whether these bundles are burstable (CPU credits) or sustained is **unverified**.
  Burstable plans would not suit the workers.
- SLA: per instance, "commercially reasonable efforts" with credits below 99.5 %
  (<https://aws.amazon.com/lightsail/sla-lightsail-instances-and-block-storage/>).

**Locaweb VPS (Brazil).** Source: <https://www.locaweb.com.br/servidor-vps/>. Unlimited
transfer. The prices are for a 24-month term, and renewal is about twice that.

| Plan | vCPU | RAM | First term | Renewal |
|---|---|---|---|---|
| VPS 8 GB | 4 | 8 GB | R$ 63,90 | R$ 124,72 |
| VPS 16 GB | 6 | 16 GB | R$ 125,90 | R$ 243,92 |
| VPS 32 GB | 8 | 32 GB | R$ 243,90 | R$ 475,92 |

- The page names no city, CPU type (dedicated or shared) or DDoS protection: all
  **unverified**.
- SLA 99.9 % for Locaweb Cloud, not stated for the VPS.

### Sessions per machine

The same model as #401, with the same unmeasured assumption: **a VPS vCPU (or a
hyperthread on bare metal) does half the work of an M3 performance core**, so one session
takes 12.8 % of a vCPU, and 0.7 / 0.128 ≈ 5.47 sessions fit per vCPU.

- Memory limit: floor((MB − 2,920) / 360).
- With the thread executor, memory per session is cut by 4× to 90 MB. The 2,920 MB idle
  figure is kept, which is conservative.
- One spare machine is added for drains: machines = ceil(200 / sessions) + 1.

| Machine | $/month | CPU limit | Memory limit (today / threads) | Fleet for 200, today | $/month | Fleet for 200, threads | $/month |
|---|---|---|---|---|---|---|---|
| Fly perf-4x 12 GB `gru` (#401) | 251.96 | 21 | 26 / 104 | 10 + 1 | 2,772 | 10 + 1 | 2,772 |
| Fly perf-4x 8 GB `gru` | 213.20 | 21 | 14 / 58 | 15 + 1 | 3,411 | 10 + 1 | 2,345 |
| Vultr `voc-c` 4 vCPU 8 GB | 80 | 21 | 14 / 58 | 15 + 1 | 1,280 | 10 + 1 | **880** |
| Vultr `voc-g` 4 vCPU 16 GB | 120 | 21 | 37 / 149 | 10 + 1 | 1,320 | 10 + 1 | 1,320 |
| **Vultr `voc-c` 8 vCPU 16 GB** | 160 | 43 | 37 / 149 | 6 + 1 | **1,120** | 5 + 1 | 960 |
| Vultr `voc-g` 8 vCPU 32 GB | 240 | 43 | 82 / 331 | 5 + 1 | 1,440 | 5 + 1 | 1,440 |
| Vultr bare metal E-2286G, 12 threads, 32 GB | 185 | 65 | 82 / 331 | 4 + 1 | 925 | 4 + 1 | 925 |
| Vultr bare metal EPYC, 16 threads, 64 GB | 365 | 87 | 173 / 695 | 3 + 1 | 1,460 | 3 + 1 | 1,460 |
| Linode `g6-dedicated-8` `br-gru` | 201.60 | 43 | 37 / 149 | 6 + 1 | 1,411 | 5 + 1 | 1,210 |
| Linode `g6-dedicated-16` `br-gru` | 403.20 | 87 | 82 / 331 | 3 + 1 | 1,613 | 3 + 1 | 1,613 |
| Lightsail Compute Optimized 16 GB | 168 | 43 | 37 / 149 | 6 + 1 | 1,176 | 5 + 1 | 1,008 |
| Vultr `vhp` 8 vCPU 16 GB (shared, reference) | 96 | 43? | 37 / 149 | 6 + 1 | 672 | 5 + 1 | 576 |

- **Pick the Vultr `voc-c` 8 vCPU / 16 GB** for today's memory profile, and the
  `voc-c` 4 vCPU / 8 GB once the thread executor is in.
- The bare-metal E-2286G is the cheapest dedicated option ($925), but each server carries
  65 sessions, so losing one takes a third of the fleet. Its 2019 CPU may also be further
  from the "half an M3 core" assumption.
- Shared plans are cheaper again, but neighbours can take their CPU at any moment, and that
  shows up as audio jitter.
- Fly and Vultr both bill by the hour up to the monthly cap
  (<https://docs.fly.io/about/pricing>), so scaling down off-peak cuts either one by the
  same share. The comparison holds.

**Egress per session.** The worker sends the learner's microphone to Deepgram the whole
session (`voice-worker/worker.py`), as 16 kHz 16-bit PCM, about 256 kbps. It also publishes
about 40 kbps of patient audio. That is about **300 kbps, or 22 MB per 10-minute station**:
450 GB/month at 20k stations, 2.25 TB at 100k. The plugin's default encoding (`linear16`)
was not checked (**unverified**). Every VPS fleet above includes 20+ TB, so this costs
nothing there. On Fly it costs **$0.04/GB** in South America
(<https://docs.fly.io/about/pricing>): about $18 or $90 a month.

## 2. Fly `gru` vs the VPS fleet, side by side

| Scenario (200 sessions) | Fly `gru` | Cheapest dedicated VPS fleet | Difference |
|---|---|---|---|
| Today, memory-bound (360 MB/session) | 11 × perf-4x 12 GB = **$2,772** + $18–90 egress | 7 × Vultr `voc-c` 8 vCPU 16 GB = **$1,120** (bare metal $925) | −$1,670 to −$1,740 (−60 %) |
| Threads, CPU-bound (90 MB, 6.4 % of an M3 core) | 11 × perf-4x 8 GB = **$2,345** + egress | 11 × Vultr `voc-c` 4 vCPU 8 GB = **$880** | −$1,480 to −$1,555 (−63 %) |

Both sides rest on the same CPU assumption. A one-hour run of
`scripts/load/run-worker-load-test.sh` on one Vultr `voc-c` machine, billed by the hour,
would replace it with a measurement (follow-up of #401).

## 3. LiveKit Cloud vs self-hosted LiveKit

### LiveKit Cloud

Source: <https://livekit.com/pricing>, <https://docs.livekit.io/home/cloud/quotas-and-limits/>,
<https://docs.livekit.io/home/cloud/billing/> (2026-10-26).

| Plan | $/month | Included WebRTC minutes | Overage per minute | Concurrent connections | Included downstream data | Data overage |
|---|---|---|---|---|---|---|
| Build | 0 | 5,000 | none listed | 100 | 50 GB | none listed |
| Ship | 50 | 150,000 | $0.0005 | 1,000 | 250 GB | $0.12/GB |
| Scale | 500 | 1.5M | $0.0004 | 5,000 | 3 TB | $0.10/GB |

- A WebRTC minute is "time that a single user is connected to LiveKit Cloud via a LiveKit
  SDK", billed per second with a 10-second minimum per session.
- The concurrent connection limit counts "connected agents and end-users across all rooms".
  200 rooms are 400 participants, so **Ship's 1,000 covers 200 sessions**.
- The concurrent **agent session** limit (20 on Ship) applies to "an actively connected agent
  running on LiveKit Cloud". The official quotas page now ties it to agents deployed to
  LiveKit Cloud, so our self-hosted workers fall outside it but count as participants. This
  moves the open item of `production-infrastructure.md` A11 forward. Still confirm it with
  LiveKit support before relying on Ship.
- Self-hosted agents pay for LiveKit's **turn detector** ($0.50 per 1,000 predictions beyond
  7,500/month) and **adaptive interruption** ($1.20 per 1,000 checks beyond 40,000). Our
  worker uses neither: it ends turns with Deepgram endpointing and has no `AgentSession`
  (`voice-worker/worker.py`), so neither applies.
- **Per station** (our estimate): 2 participants × 10 min = **20 WebRTC minutes**. Downstream
  data is about 2 × 50 kbps × 600 s ≈ **7.5 MB**. Whether the self-hosted agent's own
  connection is billed as WebRTC minutes is **unverified**: the 20 minutes assume it is. The
  Opus bitrate with overhead (about 50 kbps) is an estimate.

| Volume | Minutes | Data | Ship | Scale | Cheaper |
|---|---|---|---|---|---|
| 20k stations | 400k | 150 GB | 50 + 250k × 0.0005 = **$175** | $500 | Ship |
| 100k stations | 2M | 750 GB | 50 + 925 + 60 = $1,035 | 500 + 500k × 0.0004 = **$700** | Scale |
| 432k stations (200 concurrent, 12 h/day) | 8.64M | 3.2 TB | $4,654 | **$3,380** | Scale |

### Self-hosted requirements

From the official self-hosting docs: <https://docs.livekit.io/home/self-hosting/deployment/>,
<https://docs.livekit.io/home/self-hosting/vm/>, <https://docs.livekit.io/home/self-hosting/ports-firewall/>,
<https://docs.livekit.io/home/self-hosting/benchmark/>.

- **Ports:**
  - 443/TCP: HTTPS signalling and TURN/TLS.
  - 80/TCP: certificate issuance.
  - 7881/TCP: ICE over TCP, the fallback when UDP is blocked.
  - **50000–60000/UDP**: media; "each participant uses two ports". 7882/UDP can multiplex
    all UDP on one port instead.
  - 3478/UDP: embedded TURN/STUN.
  - 5349/TCP: TURN/TLS, or 443 without a load balancer.
  - 7880: the API, behind TLS termination.
  - 6789: Prometheus, optional.
- **TLS:** a domain with a certificate from a trusted CA ("self-signed certs do not work").
  TURN needs **its own domain and certificate**. The VM guide uses Caddy, which obtains
  Let's Encrypt or ZeroSSL certificates on its own. Both domains point to the instance.
- **TURN:** TURN/TLS on 443 has "the broadest coverage" for restrictive networks. That is
  what learners on hospital and university Wi-Fi need. TURN/UDP is optional.
- **Redis:** needed only for more than one node (multi-node routing). The config marks it
  "recommended for production deploys". A single node runs without it.
- **Capacity:** "bound by CPU and bandwidth". The docs recommend compute-optimized instances
  and 10 Gbps networking, and give **no per-participant figure** and no instance size.
  - Their audio benchmark: 10 publishers to 3,000 subscribers at 3 kbps each took 80 % of a
    16-core `c2-standard-16`. That is about 30,000 forwarded tracks.
  - Our case: 400 published and 400 subscribed tracks, about **20 Mbps out** at 200
    sessions.
  - Our own measurement: LiveKit took 14 % of one M3 core for 50 participants (#401). By that
    rate 400 participants need about 1.1 M3 cores. **A 4-vCPU dedicated node has ample
    room.**

### Self-hosted cost in São Paulo

| Setup | Monthly |
|---|---|
| One node: Vultr `voc-c` 4 vCPU 8 GB ($80) + DDoS ($10); 750 GB/month egress at 100k stations fits in its 6 TB | **$90** |
| HA: two nodes + DDoS ($180) + a small Redis VPS ($20, `vc2-2c-4gb`); a load balancer for TURN/TLS not priced | **≈ $200+** |
| Linode instead of Vultr: one `g6-dedicated-4` (DDoS included) | $101 |

### Operational burden of self-hosting

| Area | What it takes |
|---|---|
| TLS | Two domains and automatic renewal (Caddy). A failed renewal stops every new room. |
| TURN | TURN/TLS on 443 must work from learners' networks. Test from a hospital, a university and a mobile network before launch. LiveKit Cloud already solves this. |
| Single node | A reboot, a crash or an upgrade **ends every live room**. Kernel and LiveKit upgrades need the quiet-window drain, like Phoenix deploys. |
| HA | Redis, a network load balancer, and routing a room to one node. Two nodes do not keep a room alive when its node dies. |
| Monitoring | Prometheus on 6789, alerts on CPU, packet loss and node health. On Cloud this comes from LiveKit. |
| Security | Public UDP 50000–60000 and 443, DDoS protection, firewall, OS patching. |
| Region | One São Paulo node is no worse than LiveKit Cloud's Brazil edge, which has one location "with no in-region redundancy" (`production-infrastructure.md` A10). |

## 4. Options

### Totals per option

At 200 concurrent sessions, USD/month. The worker fleet is today's memory profile; the
thread-executor totals are in the [Result](#result) table.

| | (a) All Fly + LiveKit Cloud | (b) Fly Phoenix, VPS workers, LiveKit Cloud | (c) as (b) + self-hosted LiveKit | (d) All VPS |
|---|---|---|---|---|
| Phoenix | Fly perf-1x $53 | Fly perf-1x $53 | Fly perf-1x $53 | Vultr `voc-g` 2 vCPU 8 GB $60 + DDoS $10 |
| Workers | Fly $2,772 + $18–90 egress | Vultr $1,120 | Vultr $1,120 | Vultr $1,120 |
| LiveKit | Cloud $175 (20k) / $700 (100k) | Cloud $175 / $700 | Self-hosted $90 (HA ≈ $200) | Self-hosted $90 |
| **Total, 20k / 100k** | **$3,018 / $3,615** | **$1,348 / $1,873** | **$1,263 / $1,263** | **$1,280 / $1,280** |
| Setup effort | None beyond #404 (ready, not run) | 1–2 days: provision 7 VMs, Docker image, secrets, rollout script | +2–4 days: LiveKit node, DNS, Caddy, TURN tests, monitoring | +1–2 weeks: replace the Fly drain/replay design, TLS, deploys, logs |
| Main risk | Cost; the 300 s `kill_timeout` is shorter than a station | We own OS patching and the worker rollout; the CPU assumption is unmeasured | TURN from restrictive networks; a single SFU node ends all rooms on failure or upgrade | All of (c), plus our own blue/green and session routing for Phoenix |

### What changes in `deploy.md` and the #404 design

- **(a)** Nothing.
- **(b)** Phoenix is unchanged: drain, `bluegreen` and `fly-replay` all stay.
  - Only the "Voice worker" sections change. `fly deploy` / `fly scale count` become a
    rollout over the VMs: pull the image, then
    `docker stop --time 900` on one host at a time after the Phoenix drain. Docker's stop
    timeout is ours to set, so the worker can finish a 10-minute station, which Fly's 300 s
    cap cannot do.
  - `PHOENIX_URL` stays the public HTTPS URL. That is already a requirement, so worker
    requests still enter through Fly's proxy and `fly-replay` keeps reaching the owner
    machine.
  - Secrets move from `fly secrets` to a root-only env file or similar.
  - `voice-worker/fly.toml` is retired.
- **(c)** All of (b), plus:
  - `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` point to our server in both
    apps. The orphan sweep and the room API work the same against a self-hosted server.
  - deploy.md relies on "LiveKit's empty-room timeout" to close orphaned rooms. That becomes
    a value we set in `livekit.yaml` (`room.empty_timeout`).
  - LiveKit upgrades join the quiet-window procedure.
- **(d)** All of (c), plus Phoenix leaves Fly, and that breaks the #404 design:
  - **`fly-replay` and `FLY_MACHINE_ID` do not exist off Fly.** Routing a session to its
    owner during a deploy has to move to our own reverse proxy (for example an nginx `map`
    on the `<node>.` session-id prefix), and `config/runtime.exs` needs a neutral node-id
    variable.
  - `backend/lib/backend_web/plugs/session_replay.ex` has to emit something that proxy
    understands.
  - `rel/deploy.sh` (built on `fly machines list` and `fly ssh console`) has to be rewritten
    for SSH, along with the `release_command` migrations, TLS (Caddy) and
    `TRUSTED_CLIENT_IP_HEADER` (a proxy header we must strip from clients).
  - The Fly log drain alerts on the capacity lines need a replacement.
  - The alternative is a single Phoenix node with no blue/green, which brings a restart gap
    after every drain.

### Data location (LGPD), briefly

- Neon `aws-sa-east-1`, Fly `gru`, Vultr `sao` and Linode `br-gru` all keep stored data and
  compute in Brazil. The LiveKit media can stay in Brazil through region pinning to `sa`, or
  by self-hosting.
- That still does not put everything in Brazil: Deepgram, Cartesia, Anthropic and TypeSafe
  process audio and text outside the country in every option. So LGPD's rules for
  international transfers (Art. 33, for example ANPD's standard contractual clauses) apply
  whatever is chosen here.
- Vultr, Akamai, AWS and Fly are US companies even when the datacenter is in Brazil. Locaweb
  and Magalu are Brazilian. This is not legal advice: the privacy review of #183 owns it.

## Open checks

- Run the load harness on one Vultr `voc-c` machine in `sao` to measure the CPU.
- Measure the latency from Vultr `sao` to LiveKit Cloud's Brazil edge, to Fly `gru` and to
  Neon `aws-sa-east-1`.
- Confirm with LiveKit support that self-hosted agents are outside the agent-session limit,
  and whether their connection is billed as WebRTC minutes.
- Vultr SLA terms, the current egress pooling, and Lightsail's São Paulo overage rate and
  whether its bundles are burstable.
- Magalu Cloud prices in BRL (calculator only), and Locaweb's city and CPU type.
- If (c) is chosen: TURN/TLS on 443 from restrictive networks.
