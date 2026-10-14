# AGENTS.md

This branch builds the GitHub Actions runner images (Ubuntu 22.04, 24.04 and
26.04, x64 and arm64) as LXD container and virtual machine images with the
`hashicorp/lxd` Packer plugin, instead of Azure images. The Windows and
Azure parts of the repository are not maintained here.

## Layout

- `.github/workflows/build-lxd-images.yml`: the reusable workflow, called by
  `ubuntu*.yml`. A `capabilities` job detects `/dev/kvm` on the runner type of
  the build, and the `build` job runs one matrix job per instance type.
- `helpers/GenerateResourcesAndImage.ps1`: what the workflow runs; also usable
  locally with `Import-Module` and `GenerateResourcesAndImage -ImageType
  Ubuntu2404 -InstanceType container`. It installs the plugin, validates and
  builds one source (`<build>.lxd.container` or `<build>.lxd.vm`).
- `images/ubuntu/templates/`: the Packer templates; sources are `container`
  and `vm` in `source.ubuntu.pkr.hcl`.

## Things to know

- Packer runs every provisioner as root through `lxc exec`. Run what must not
  be root (Homebrew) with `su --login packer --command ...`.
- `lxc file push` creates single files with mode 0600 and directories with
  their sources' modes; upload directories with a trailing slash to push their
  contents.
- Unauthenticated `api.github.com` requests are limited per source IP.
  `get_github_api_json` sends `GITHUB_TOKEN`; the template variable
  `github_token` hands it to the provisioners that need it. Use that helper
  instead of calling `curl` on the API.
- The image version is `<yyyyMMdd>.<run_number>.<run_attempt>`, passed as
  `PKR_VAR_image_version`; local builds use `dev`.
- Containers have no grub and no reboot; check with
  `systemd-detect-virt --container` before touching boot configuration.
- With `pull_request_target`, workflow files are read from `main`, not from
  the pull request head. Changes under `images/` do come from the head.

## Conventions

- One atomic change per commit; keep commits small and fix up the commit a
  change belongs to instead of adding corrections on top.
- Delete what the lxd builds don't need rather than commenting it out.
- Don't push, force-push or rewrite history unless asked.
