# Script to create Build and Release defintions

$userName = "nate.duff@outlook.com"
$organization = "NateDuff"
$project = "SimpleAuth"
$buildName = "Web Build"
$releaseName = "Web Release"
$manifestPath = "WebBuild.yml"
$publicBuildVariables = @(
    @{
        Name = "BuildConfig"
        Value = "Debug"
    }
)
$secretBuildVariables = @()
$publicReleaseVariables = @()
$secretReleaseVariables = @(
    @{
        Name = "DevConnectionString"
        Value = "SecretHiddenValue"
    }
)

Function Get-DeployVariables ($publicVariables, $secretVariables) {
    $output = @{}

    foreach ($var in $publicVariables) {
        $output += @{
            $var.Name = @{
                value = $var.Value
                isSecret = $false
            }
        }
    }

    foreach ($var in $secretVariables) {
        $output += @{
            $var.Name = @{
                value = $var.Value
                isSecret = $true
            }
        }
    }

    return $output
}

Function Get-AuthToken ([pscredential]$creds) {
    $pair = "$($creds.UserName):$($creds.GetNetworkCredential().Password)"
    
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    
    return [System.Convert]::ToBase64String($bytes)
}

Function New-BuildDefinition {
Param(
    [string]$org, 
    [string]$project, 
    [string]$buildName, 
    [pscredential]$creds, 
    [string]$manifestPath,
    $publicBuildVariables,
    $secretBuildVariables
)
    $uri = "https://dev.azure.com/$org/$project/_apis/build/definitions`?api-version=5.0-preview.7"

    $payload = @{
        name = $buildName
        buildNumberFormat = "`$(Build.DefinitionName)-`$(date:yyyyMMdd)`$(rev:.r)"
        badgeEnabled = $true
        queue = @{
            name = "Hosted"
        }
        repository = @{
            name = "SimpleAuth"
            defaultBranch = "refs/heads/master"
            clean = $true
            type = "TfsGit"
            properties = @{
                cleanOptions = 1
                reportBuildStatus = $true
            }
        }
        process = @{
            yamlFilename = $manifestPath
            type = 2
        }
        variables = Get-DeployVariables $publicBuildVariables $secretBuildVariables
    }

    $newBuildParams = @{
        uri = $uri 
        Method = "Post"
        Body = ($payload | ConvertTo-Json -Compress)
        Headers = @{
            Authorization = ("Basic {0}" -f (Get-AuthToken -creds $creds))
        }
        Credential = $creds
        ContentType = "application/json"
    }

    (Invoke-WebRequest @newBuildParams).Content | ConvertFrom-Json
}

Function Get-DeploymentPhases ([string]$environmentName) {
    $hostedQueue = @{
        queueId = 20
    }

    $deployPhases = @(
        @{
            name = "Stage $environmentName Environment"
            phaseType = "agentBasedDeployment"
            rank = 1
            deploymentInput = $hostedQueue
        },
        @{
            name = "Deploy to $environmentName"
            phaseType = "agentBasedDeployment"
            rank = 2
            deploymentInput = $hostedQueue
        }
    )

    if ($environmentName -eq "Prod") {
        return $deployPhases
    } else {
        return @(
            $deployPhases
            @{
                name = "Cleanup $environmentName Environment"
                phaseType = "agentBasedDeployment"
                rank = 3
                deploymentInput = $hostedQueue
            }
        )
    }
}

Function New-Environment ([string]$environmentName, [int]$rank) {
    switch ($environmentName) {
        "Dev" {
            $condition = @{
                name = "ReleaseStarted"
                conditionType = "event"
            }
        }
        "Test" {
            $condition = @{
                name = "Dev"
                conditionType = "environmentState"
                value = 4
            }
        }
        "Prod" {
            $condition = @{
                name = "Test"
                conditionType = "environmentState"
                value = 6
            }
        }
    }

    return @{
        name = $environmentName
        rank = $rank
        source = "restApi"
        conditions = @(
            $condition
        )
        retentionPolicy = @{
            daysToKeep = 30
            releasesToKeep = 3
            retainBuild = $true
        }
        executionPolicy = @{
            concurrencyCount = 1
            queueDepthCount = 0
        }
        deployPhases = @(Get-DeploymentPhases $environmentName)
        environmentOptions = @{
            badgeEnabled = $true
            autoLinkWorkItems = $true
            publishDeploymentStatus = $true
        }
        preDeployApprovals = @{
            approvals = @(
                @{
                    isAutomated = $true
                    rank = 1
                    isNotification = $false
                    id = 1
                }
            )
        }
        preDeploymentGates = @{
            gates = $null
        }
        postDeployApprovals = @{
            approvals = @(
                @{
                    isAutomated = $true
                    rank = 1
                    isNotification = $false
                    id = 1
                }
            )
        }
        postDeploymentGates = @{
            gates = $null
        }
    }
}

Function New-ReleaseDefinition {
Param(
    [string]$org, 
    [string]$project, 
    [string]$releaseName, 
    [pscredential]$creds, 
    [string]$buildName, 
    [string]$buildID,
    [string]$projectID,
    $publicReleaseVariables,
    $secretReleaseVariables
)
    $uri = "https://vsrm.dev.azure.com/$org/$project/_apis/release/definitions?api-version=5.0-preview.3"

    $payload = @{
        name = $releaseName        
        releaseNameFormat = "Release-`$(rev:r)"
        artifacts = @(
            @{
                definitionReference = @{
                    definition = @{
                        id = $buildID
                        name = $buildName
                    }
                    project = @{
                        id = $projectId
                        name = $project
                    }
                }
                isPrimary = $true
                isRetained = $false
                alias = $buildName
                type = "Build"
            }
        )
        environments = @(
            (New-Environment -environmentName "Dev" -rank 1),
            (New-Environment -environmentName "Test" -rank 2),
            (New-Environment -environmentName "Prod" -rank 3)
        )
        triggers = @(
            @{
                artifactAlias = "New Build"
                triggerType = "artifactSource"
            }
        )
        variables = Get-DeployVariables $publicReleaseVariables $secretReleaseVariables
    }

    $newReleaseParams = @{
        uri = $uri 
        Method = "Post"
        Body = ($payload | ConvertTo-Json -Compress -Depth 100)
        Headers = @{
            Authorization = ("Basic {0}" -f (Get-AuthToken -creds $creds))
        }
        Credential = $creds
        ContentType = "application/json"
    }

    (Invoke-WebRequest @newReleaseParams).Content | ConvertFrom-Json
}

$baseParams = @{
    org = $organization 
    project = $project    
    creds = (Get-Credential -UserName $userName -Message "Enter your password:")
    buildName = $buildName
}

$buildParams = @{
    manifestPath = $manifestPath
    publicBuildVariables = $publicBuildVariables
    secretBuildVariables = $secretBuildVariables
}

$build = New-BuildDefinition @baseParams @buildParams

$releaseParams = @{
    releaseName = $releaseName    
    buildID = $build.id
    projectID = $build.project.id
    publicReleaseVariables = $publicReleaseVariables
    secretReleaseVariables = $secretReleaseVariables
}

$release = New-ReleaseDefinition @baseParams @releaseParams

$release