$ErrorActionPreference = 'Stop'

enum ImageType {
    Ubuntu2204       = 1
    Ubuntu2204_Arm64 = 2
    Ubuntu2404       = 3
    Ubuntu2404_Arm64 = 4
    Ubuntu2604       = 5
    Ubuntu2604_Arm64 = 6
}

Function Get-PackerTemplate {
    param (
        [Parameter(Mandatory = $True)]
        [string] $RepositoryRoot,
        [Parameter(Mandatory = $True)]
        [ImageType] $ImageType
    )

    switch ($ImageType) {
        # Note: Double Join-Path is required to support PowerShell 5.1
        ([ImageType]::Ubuntu2204) {
            $relativeTemplatePath = Join-Path (Join-Path "ubuntu" "templates") "build.ubuntu-22_04.pkr.hcl"
            $imageOS = "ubuntu22"
        }
        ([ImageType]::Ubuntu2204_Arm64) {
            $relativeTemplatePath = Join-Path (Join-Path "ubuntu" "templates") "build.ubuntu-22_04-arm64.pkr.hcl"
            $imageOS = "ubuntu22-arm64"
        }
        ([ImageType]::Ubuntu2404) {
            $relativeTemplatePath = Join-Path (Join-Path "ubuntu" "templates") "build.ubuntu-24_04.pkr.hcl"
            $imageOS = "ubuntu24"
        }
        ([ImageType]::Ubuntu2404_Arm64) {
            $relativeTemplatePath = Join-Path (Join-Path "ubuntu" "templates") "build.ubuntu-24_04-arm64.pkr.hcl"
            $imageOS = "ubuntu24-arm64"
        }
        ([ImageType]::Ubuntu2604) {
            $relativeTemplatePath = Join-Path (Join-Path "ubuntu" "templates") "build.ubuntu-26_04.pkr.hcl"
            $imageOS = "ubuntu26"
        }
        ([ImageType]::Ubuntu2604_Arm64) {
            $relativeTemplatePath = Join-Path (Join-Path "ubuntu" "templates") "build.ubuntu-26_04-arm64.pkr.hcl"
            $imageOS = "ubuntu26-arm64"
        }
        default { throw "Unknown type of image" }
    }

    $imageTemplatePath = [IO.Path]::Combine($RepositoryRoot, "images", $relativeTemplatePath)
    # Specific template selection using Packer's "-only" functionality
    $buildName = [IO.Path]::GetFileName($imageTemplatePath).Split(".")[1]

    if (-not (Test-Path $imageTemplatePath)) {
        throw "Template for image '$ImageType' doesn't exist on path '$imageTemplatePath'."
    }

    return [PSCustomObject] @{
        "BuildName" = $buildName
        "ImageOS"   = $imageOS
        "Path"      = [IO.Path]::GetDirectoryName($imageTemplatePath)
    }
}

Function Show-LatestCommit {
    [CmdletBinding()]
    param()

    process {
        $latestCommit = (git --no-pager log --pretty=format:"Date: %cd; Commit: %H - %s; Author: %an <%ae>" -1)
        Write-Host "Latest commit: $latestCommit."
    }
}

Function GenerateResourcesAndImage {
    <#
        .SYNOPSIS
            A helper function to help generate an image.
        .DESCRIPTION
            This function will build the LXD image of the specified image type with Packer.
        .PARAMETER ImageType
            The type of image to generate. Valid values are: Ubuntu2204, Ubuntu2204_Arm64, Ubuntu2404, Ubuntu2404_Arm64, Ubuntu2604, Ubuntu2604_Arm64.
        .PARAMETER InstanceType
            The type of LXD instance to build the image from. Valid values are: container, vm. The default is 'container'.
        .PARAMETER ImageGenerationRepositoryRoot
            The root directory of the image generation repository. This is used to locate the packer template.
        .PARAMETER OnError
            Specify how packer handles an error during image creation.
            Options:
                abort - abort immediately
                ask - ask user for input
                cleanup - attempt to cleanup and then abort
                run-cleanup-provisioner - run the cleanup provisioner and then abort
            The default is 'ask'.
        .PARAMETER PluginVersion
            Specify the version of the packer LXD plugin to use. The default is "1.0.3".
        .EXAMPLE
            GenerateResourcesAndImage -ImageGenerationRepositoryRoot "$HOME/runner-images" -ImageType Ubuntu2204 -InstanceType vm
    #>
    param (
        [Parameter(Mandatory = $True)]
        [ImageType] $ImageType,
        [Parameter(Mandatory = $False)]
        [ValidateSet("container", "vm")]
        [string] $InstanceType = "container",
        [Parameter(Mandatory = $False)]
        [string] $ImageGenerationRepositoryRoot = $pwd,
        [Parameter(Mandatory = $False)]
        [string] $PluginVersion = "1.0.3",
        [Parameter(Mandatory = $False)]
        [ValidateSet("abort", "ask", "cleanup", "run-cleanup-provisioner")]
        [string] $OnError = "ask"
    )

    Show-LatestCommit -ErrorAction SilentlyContinue

    # Validate packer is installed
    $PackerBinary = Get-Command "packer"
    if (-not ($PackerBinary)) {
        throw "'packer' binary is not found on PATH."
    }

    # Get template path
    $PackerTemplate = Get-PackerTemplate -RepositoryRoot $ImageGenerationRepositoryRoot -ImageType $ImageType
    Write-Debug "Template path: $($PackerTemplate.Path)."

    Write-Host "Downloading packer plugins..."
    & $PackerBinary plugins install github.com/hashicorp/lxd $PluginVersion

    if ($LastExitCode -ne 0) {
        throw "Packer plugins download failed."
    }

    Write-Host "Validating packer template..."
    & $PackerBinary validate `
        "-only=$($PackerTemplate.BuildName).lxd.$($InstanceType)" `
        "-var=image_os=$($PackerTemplate.ImageOS)" `
        $PackerTemplate.Path

    if ($LastExitCode -ne 0) {
        throw "Packer template validation failed."
    }

    try {
        & $PackerBinary build -on-error="$($OnError)" `
            -only "$($PackerTemplate.BuildName).lxd.$($InstanceType)" `
            -var "image_os=$($PackerTemplate.ImageOS)" `
            $PackerTemplate.Path

        if ($LastExitCode -ne 0) {
            throw "Failed to build image."
        }
    } catch {
        Write-Error $_
    }
}
