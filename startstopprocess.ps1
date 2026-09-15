#ETAPE 01 - On demande à l'utilisateur un nom de service à chercher de type string
$AskUserServiceToCheck = Read-Host "Service Windows à checker"

#ETAPE 02 - On vérifie via Get-Service si le service existe bien
if(($CheckIfExist = Get-Service -Name $AskUserServiceToCheck -ErrorAction SilentlyContinue)) {
    Write-Host "$($CheckIfExist.Name) found !"
} else {
    Write-Host "Service unknown"
    exit
}

# ETAPE 03 - On affiche l'état
Write-Host "Current State of service is $($CheckIfExist.Status)"

# ETAPE 04 - On vérifie son état: running/stopped. Si stopped on propose de le lancer, si running de le stopper.
if($CheckIfExist.Status -eq "Stopped"){
    $answer = Read-Host "Voulez vous le lancer ? yes|no "
    $answer = $answer.Trim()
    if($answer.ToLower() -eq "yes" -or $answer.ToLower() -eq "y"){
        Start-Service -Name $AskUserServiceToCheck
    } 
} elseif ($CheckIfExist.Status -eq "Running"){
    $answer = Read-Host "Voulez vous l'arrêter ? yes|no "
    $answer = $answer.Trim()
    if($answer.ToLower() -eq "yes" -or $answer.ToLower() -eq "y"){
        Stop-Service -Name $AskUserServiceToCheck
    }
} else {
    Write-Host "Error, status inconnu"
}

# ETAPE 05 - Message confirmant le nouvel état du service
Write-Host "New State of service is $((Get-Service -Name $AskUserServiceToCheck).Status)"