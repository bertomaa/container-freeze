# Cloud Native Summit Munich Session Submission Draft

## Session Title

`Don't Kill the Pod Yet: Detecting and Capturing Fileless Malware in Kubernetes`

## Description

In Kubernetes incident response, the first priority is usually containment: stop the workload, isolate it, or replace it quickly. But for fileless attacks, that standard response can also destroy the most valuable evidence, because the payload and stolen data may exist only in memory.

This session presents a practical incident response workflow for Kubernetes that focuses on what happens after detection. Using open source tools, I will show how suspicious behavior can be detected at the syscall level with Tetragon, how a malicious process can be frozen instead of killed, and how CRIU can capture the container's memory state before the evidence disappears. The result is a forensic snapshot that preserves the in-memory payload, process state, and data that may otherwise be lost forever.

The talk is built around a live demo and open source proof of concept called Container Freeze. The scenario simulates a supply-chain style compromise in which a backdoored application downloads and executes code entirely in memory after being triggered through an otherwise normal health endpoint. From there, the session walks through the full response flow: detect, freeze, checkpoint, isolate, and analyze.



## How will your presentation benefit the ecosystem?

This talk shows how Tetragon and CRIU can be combined into a working incident response workflow and presents a concrete alternative to the standard "delete and replace" response for situations where preserving forensic evidence matters. The demo is fully reproducible and open source, so attendees can run the full scenario in their own environment and evaluate whether the approach fits their setup.

## Session Format

Suggested: `Conference talk / breakout session`

Ideal length: `30 minutes`

## Do you have another session type in mind?

If a shorter format is preferred, this could also work well as a `15-minute lightning talk` with a tighter focus on the incident response workflow and lessons learned.

## Talk Type

Suggested: `Technical talk`

Audience level: `Intermediate`

## Category

Suggested: `Cloud Native and Open Source`

## Additional Resources

- Supporting article: `https://blog.marcobertolino.dev/blog/detecting-and-capturing-fileless-malware-in-kubernetes/`
- Project repository: `https://github.com/bertomaa/container-freeze`

## Open Source Projects

- Kubernetes
- K3s
- Tetragon
- CRIU
- containerd
- Cilium ecosystem

## Case Study

`No`

## Presented this talk before

`No`

This would be a new talk prepared for Cloud Native Summit Munich.

## Sponsor Talk

`No`

This is not a sponsor talk. It is based on open source tooling and a community-oriented technical case study.
