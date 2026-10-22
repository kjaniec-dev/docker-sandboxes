# CA maintenance after SBX 0.49.2

Docker published [SBX 0.49.2](https://github.com/docker/sbx-releases/releases/tag/v0.49.2)
with Go 1.27.3 and llmman 0.1.571 following the eMudhra intermediate CA compromise.
Its [security advisory](https://docs.docker.com/security/security-announcements/#docker-sandboxes-response-to-emudhra-ca-compromise)
explicitly requires separate action for existing sandboxes and custom templates.

Raising this repository's CLI minimum does not certify or modify the trust stores of existing
VMs. The previously recorded 0.49.1 infrastructure smoke matrix did not test CA distrust.

## Preserve an existing sandbox

Record the sandbox's name and running/stopped state using `sbx ls --json`. Start stopped
sandboxes through their existing environment/launcher configuration before maintenance.
For an Ubuntu-based sandbox, use Docker's documented package update path:

```bash
sbx exec <sandbox-name> -- sudo apt-get update
sbx exec <sandbox-name> -- sudo apt-get install --only-upgrade -y ca-certificates
sbx exec <sandbox-name> -- dpkg-query -W ca-certificates
```

Check the installed package against the distribution's security update, then restart
applications that may hold the old trust store in memory. Return previously stopped
sandboxes to their original state after maintenance. These commands preserve the VM and
its files; they do not update application-specific CA bundles.

## Application-specific trust stores

Audit the actual runtime used by each agent and tool, including the shared JDK under
`/opt/sbx-dev/java`, Node.js/Bun, Python environments and certifi, and uv. Updating Ubuntu's
`ca-certificates` alone is not proof that these independent trust stores reject the affected
chains. Use patched releases from their maintainers, rebuild affected tools where necessary,
and verify distrust separately from ordinary successful HTTPS or model requests.

The [incident response index](https://emudhra.we-have-a-problem.com/#who-has-patched)
links the affected intermediates, offline certificate chains and vendor updates. For example,
the [Go security announcement](https://groups.google.com/g/golang-announce/c/66pojueaQek)
identifies 1.27.3 and 1.26.10 as patched versions. A tool built with an earlier Go release
may need recompilation even if the system CA package has been updated.

## New sandboxes and custom kits

`env/common.sbxenv.yaml` already sets `sandboxOptions.pullPolicy: always`. However, the
agent references in this repository use immutable digests: pulling the same digest again
cannot fetch a rebuilt replacement artifact. Resolve an updated official artifact explicitly
and change its pin only after native validation and the relevant profile's smoke test.

The custom Claude/OpenCode workloads inherit `docker/sandbox-templates:shell-docker`, and
`mixins/dev` builds tools from additional base images and downloaded runtimes. Refresh those
inputs and rebuild source kits before using them to claim CA remediation. A cached kit build
or a successful environment plan alone is not evidence that those inputs were refreshed.

Recreation with refreshed images is Docker's alternative mitigation. Before removing an
existing sandbox, preserve VM-local files, unpushed commits and other state. Recreate it with
the original environment files and approved local overlays; CLI upgrade, CA package maintenance
and sandbox recreation are separate operations.
