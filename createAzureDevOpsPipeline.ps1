# Script to create Build and Release defintions
Param(
    $userName = "nate.duff@outlook.com",
    $organization = "NateDuff",
    $project = "SimpleAuth",
    $buildName = "Test Build",
    $releaseName = "Test Release",
    $manifestPath = "WebBuild.yml",
    $publicBuildVariables = @(
        @{
            Name = "BuildConfig"
            Value = "Debug"
        }
    ),
    $secretBuildVariables = @(),
    $publicReleaseVariables = @(),
    $secretReleaseVariables = @(
        @{
            Name = "DevConnectionString"
            Value = "SecretHiddenValue"
        }
    )
)

Import-Module ".\OneDrive\Documents\WindowsPowershell\Scripts\AzureDuffOpsPipelines.psm1"

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

#Delete-BuildDefinition -org $org -project $project -creds $creds -buildDefinitionID $build.id
#Delete-ReleaseDefinition -org $org -project $project -creds $creds -releaseDefinitionID $release.id
