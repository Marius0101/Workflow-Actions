#-------------------------------------------------------------------------------[Parameters]-------------------------------------------------------------------------------
param(
    [Parameter(Mandatory)]
    [string]
    $token,
    [Parameter(Mandatory)]
    [string]
    $owner,
    [Parameter(Mandatory)]
    [string]
    $repo,
    [Parameter(Mandatory)]
    [string]
    $baseBranch,
    [Parameter(Mandatory)]
    [string]
    $headBranch,
    [string]
    $title,
    [string]
    $body,
    [string]
    $modify,
    [string]
    $assignees,
    [string]
    $reviewers,
    [string]
    $teamReviewers
)
#-------------------------------------------------------------------------------[Functions]-------------------------------------------------------------------------------
function Get-ValidUsers{
    param (
        [System.Collections.ArrayList] 
        $users,
        [System.Object[]]
        $expectedUsers
    )
    [System.Collections.ArrayList]$validUsers = [System.Collections.ArrayList]::new()
    foreach ($user in $users){
        [System.Object]$expectedUser = $expectedUsers | Where-Object { $_.login -eq $user }
        if($expectedUser.Count -gt 0){
            Write-Host "User $user is a valid user."
            $null = $validUsers.Add($user)
        }
        else {
            Write-Host "User $user is an invalid user. Removing from list"
        }
    }
    return ,@($validUsers)
}

function ConvertTo-Array{
    param (
        [string]
        $inputString
    )

    [System.Collections.ArrayList]$list = [System.Collections.ArrayList]::new()

    if(-not ([string]::IsNullOrEmpty($inputString))){
        [string[]]$splitArray = $inputString -split "\s+" | Where-Object { $_ -ne "" }
    # [System.Collections.ArrayList]$list = [System.Collections.ArrayList]@($inputString -split "\s+"| Where-Object { $_ -ne "" })
        $list.AddRange($splitArray)
    }

    return ,@($list)
}

function Invoke-GitHubAPI{
    param (
        [string]
        $uri,
        [string]
        $method,
        [hashtable]
        $header,
        [hashtable]
        $body,
        [string]
        $contentType
    )
    
    if( $null -ne $body){
        [psobject]$jsonBody = $body | ConvertTo-Json
    }

    try{
        $response = Invoke-RestMethod -Uri $uri -Method $method -Headers $header -Body $jsonBody -ContentType $contentType
    }
    catch{
    [string]$errorResponse = @"

Houston, this is the problem. Please resolve it before trying again.
=======================================================================
Error Message: 
    $($_.Exception.Message)
=======================================================================
"@
        #Write-Error -Message $errorResponse -Category InvalidResult -ErrorId "APIError" -ErrorAction Stop
        Write-Error -Message $errorResponse -Category InvalidResult -ErrorAction "Stop"
        
        # Optionally, throw the error again if you want to stop execution
    }
    Write-Output "$response"
    return $response
}

#--------------------------------------------------------------------------------[Sourcing]-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------[Trap Error]------------------------------------------------------------------------------
trap{
    Write-Host "$($_.Exception.Message)" -ForegroundColor Red
    throw $Script:ErrorMsg
}
#-------------------------------------------------------------------------------[Execution]-------------------------------------------------------------------------------

[System.Collections.ArrayList]$Script:listAssignees
[System.Collections.ArrayList]$Script:listReviewers
[System.Collections.ArrayList]$Script:listTeamReviewers
$Script:ErrorMsg = "The script fail check error mesage above for more information"
if ([string]::IsNullOrEmpty($title)) {
    $title = "Merge $baseBranch branch into the $headBranch branch"
}
if (($modify -ne "true") -and  ($modify -ne "false")) {
    [string]$error = @'
Houston, we have a problem. 
---------------------------------------------
Error Message:
    The modify parameter should be set on true or false.
'@
    Write-Error -Message $error  -ErrorAction Stop
}
$modifyBoolean = [System.Convert]::ToBoolean($modify) 
$Script:listAssignees = ConvertTo-Array -inputString $assignees
$Script:listReviewers = ConvertTo-Array -inputString $reviewers
$Script:listTeamReviewers = ConvertTo-Array -inputString $teamReviewers

[hashtable]$headers = @{
    "Authorization" = "Bearer $token"
    "Accept" = "application/vnd.github.v3+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

Write-Output "::group:: Check if users are colaborators"
$Script:Uri = "https://api.github.com/repos/$owner/$repo/collaborators"
$responseColaborators = Invoke-GitHubAPI `
    -uri $Script:Uri `
    -method Get `
    -header $headers `
    -contentType "application/json"
$Script:listAssignees = Get-ValidUsers -users $Script:listAssignees -expectedUsers $responseColaborators 
$Script:listReviewers = Get-ValidUsers -users $Script:listReviewers -expectedUsers $responseColaborators 
Write-Output "The following users are assignees to PR: $Script:listAssignees"
Write-Output "The following users are reviewers to PR: $Script:listReviewers"
Write-Output "::endgroup:: "


$Script:Uri = "https://api.github.com/repos/$owner/$repo/teams"
$responseTeams = Invoke-GitHubAPI `
    -uri $Script:Uri `
    -method Get `
    -header $headers `
    -contentType "application/json"

$Script:Uri = "https://api.github.com/repos/$owner/$repo/pulls"
[hashtable]$Script:bodyVariables = @{
    "title" = $title
    "head" = $headBranch
    "base" = $baseBranch
    "body"= $body
    "maintainer_can_modify"=  $modifyBoolean
}

Write-Output "::group:: Create pull request"
$responseCreatePull = Invoke-GitHubAPI `
    -uri $Script:Uri `
    -method Post `
    -header $headers `
    -body $Script:bodyVariables `
    -contentType "application/json"
$url=$responseCreatePull[1].url
$prNumber = $responseCreatePull[1].number
Write-Output "Pull request created: $url"
Write-Output "::endgroup:: "

Write-Output "::group:: Assignees to pull request"
$Script:Uri = "https://api.github.com/repos/$owner/$repo/issues/$prNumber/assignees"
[hashtable]$Script:bodyVariables = @{
    "assignees" = $Script:listAssignees
}
$responseAssignees= Invoke-GitHubAPI `
    -uri $Script:Uri `
    -method Post `
    -header $headers `
    -body $Script:bodyVariables `
    -contentType "application/json"
Write-Output $responseAssignees
Write-Output "The following users are assigne to PR: $Script:listAssignees"
Write-Output "::endgroup:: "

Write-Output "::group:: Add reviewers to pull request"
$Script:Uri = "https://api.github.com/repos/$owner/$repo/pulls/$prNumber/requested_reviewers"
[hashtable]$Script:bodyVariables = @{
    "reviewers" = $Script:listReviewers
    "team_reviewers" = $Script:listTeamReviewers
}
$responseReviewers= Invoke-GitHubAPI `
    -uri $Script:Uri `
    -method Post `
    -header $headers `
    -body $Script:bodyVariables `
    -contentType "application/json"
Write-Output $responseReviewers
Write-Output "The following users are added as reviewers to PR: $Script:listReviewers"
Write-Output "The following teams are added as reviewers to PR: $Script:listTeamReviewers"
Write-Output "::endgroup:: "
