# Pre-reqs: Install "az cli" module
# `choco install azure-cli`

Param(
    [Parameter(Mandatory=$true)]
    [string[]] $groupIds,
    [Parameter(Mandatory=$true)]
    [int] $pollTime
)

function MapObject($objArray) {
    return ConvertFrom-Json $($objArray -join '')
}

function GetUser() {
    return MapObject($(az ad signed-in-user show 2> $null))
}

function GetGroup([string] $groupId) {
    return MapObject($(az ad group show --group $groupId 2> $null))
}

function GetCurrentUser() {
    $user = GetUser

    if (!$user) {
        az login *> $null
        $user = GetUser
    }

    return $user
}

function GetGroups([string[]] $groupIds) {
    if (!$groupIds) {
        Write-Output "No groupIds provided"
        return
    }

    $groups = @(foreach($groupId in $groupIds) { GetGroup($groupId) })

    if (!$groups) {
        Write-Output "No groups found"
        return
    }

    return $groups
}

function RemoveFromGroups($user, $groups) {
    foreach($group in @($groups)) {
        Write-Host "Checking Membership of $($group.displayName) ($($group.id)) for user $($user.displayName) ($($user.id))"
        $isMember = MapObject(az ad group member check --group $group.id --member-id $user.id 2> $null)

        if ($isMember.value) {
            Write-Host "$($user.displayName) ($($user.id)) is a member of $($group.displayName) ($($group.id))"
            $removeResult = MapObject($(az ad group member remove --group "e4a3924d-2b78-4838-b3ca-7daec99433f9" --member-id $user.id) 2> $null)

            Write-Host $removeResult;
        }
    }
}

function ConfigureTimer(
    [System.Timers.Timer] $timer, 
    [int] $timeInSeconds
) {
    $timer.Interval = ($timeInSeconds * 1000.0) #mS
    $timer.AutoReset = $true
}

function Main() {

    Write-Output "Getting User"
    $user = GetCurrentUser;

    if (!$user) {
        Write-Output "Couldn't get current user"
        return;
    }

    Write-Output "Found user"
    Write-Output "$($user.displayName), $($user.id)"

    Write-Output "Getting Groups"
    $groups = GetGroups($groupIds);

    if (!$groups) {
        Write-Output "Couldn't get groups"
        return;
    }
    Write-Output "Found groups"
    Write-Output @(foreach($group in $groups) { "$($group.displayName), $($group.id)" })

    $timer = New-Object System.Timers.Timer

    $objectEventSourceArgs = @{
        InputObject = $timer
        EventName = 'Elapsed'
        SourceIdentifier = $sourceIdentifier
        Action = { 
            RemoveFromGroups -user $Event.MessageData.user -groups $Event.MessageData.groups 
        }
        MessageData = New-Object PSObject -property @{ user = $user; groups = $groups}
    }
    ConfigureTimer -timer $timer -timeInSeconds $pollTime

    $timerInterval = if (($timer.Interval / 1000.0) -ge 3600.0) { "$(($timer.Interval / 1000.0) / 3600.0) hours" }
        elseif (($timer.Interval / 1000) -ge 60) { "$(($timer.Interval / 1000.0) / 60.0) minutes" }
        else { "$(($timer.Interval / 1000.0) ) seconds" }

    Write-Host "New timer, interval $timerInterval"

    Register-ObjectEvent @objectEventSourceArgs *> $null
    $timer.Enabled = $true

    Write-Output "Start polling..."
    RemoveFromGroups -user $user -groups $groups
    Wait-Event $sourceIdentifier
}

try {
    Set-Variable -Option ReadOnly -Name 'sourceIdentifier' -Value 'StayOutOfGroup.Timer.Elapsed'
    Main
}
catch {
    Write-Output $_
}
finally {
    Unregister-Event -SourceIdentifier $sourceIdentifier
    Remove-Variable -Name 'sourceIdentifier' -Force
}

trap {
    Unregister-Event -SourceIdentifier $sourceIdentifier
    Remove-Variable -Name 'sourceIdentifier' -Force
}