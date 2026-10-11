<#
.SYNOPSIS
    Lab de IAM (Microsoft Entra ID) - Etapa 3: ciclo de vida de identidades (Joiner / Mover / Leaver).

.DESCRIPTION
    Joiner : cria o usuário, define departamento e o adiciona ao grupo da área.
    Mover  : troca o departamento, remove o usuário dos grupos antigos e o adiciona ao grupo novo.
             Avisa se ainda houver funções administrativas atribuídas (revisão manual).
    Leaver : desativa a conta, revoga as sessões ativas e remove o usuário de todos os grupos.
             A conta NÃO é excluída (fica disponível para auditoria e retenção).

    Toda ação é registrada em jml-log.csv (data/hora, ação, usuário, detalhe).
    Senhas temporárias vão para senhas-temporarias.csv (NÃO versionar no Git).

.EXAMPLE
    .\02-jml.ps1 -Acao Joiner -Dominio "seudominio.onmicrosoft.com" -Usuario gabriel.ti -Nome "Gabriel (TI)" -Departamento TI -Grupo GRP-TI
    .\02-jml.ps1 -Acao Mover  -Dominio "seudominio.onmicrosoft.com" -Usuario gabriel.ti -Departamento Financeiro -Grupo GRP-Financeiro
    .\02-jml.ps1 -Acao Leaver -Dominio "seudominio.onmicrosoft.com" -Usuario gabriel.ti
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Joiner', 'Mover', 'Leaver')]
    [string]$Acao,

    [Parameter(Mandatory = $true)]
    [string]$Dominio,

    [Parameter(Mandatory = $true)]
    [string]$Usuario,

    [string]$Nome,
    [string]$Departamento,
    [string]$Grupo,
    [switch]$CodigoDeDispositivo
)

$ErrorActionPreference = 'Stop'

# --- Módulos e login ----------------------------------------------------------
$modulosNecessarios = 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Groups'
foreach ($modulo in $modulosNecessarios) {
    if (-not (Get-Module -ListAvailable -Name $modulo)) {
        Write-Host "Instalando o módulo $modulo ..."
        Install-Module $modulo -Scope CurrentUser -Force
    }
}

$escopos = "User.ReadWrite.All", "Group.ReadWrite.All", "Directory.Read.All"

# Desativa o login pelo Web Account Manager (WAM): evita erros de thread/runspace e de token expirado
try { Set-MgGraphOption -DisableLoginByWAM $true } catch { }
if ($CodigoDeDispositivo) {
    Connect-MgGraph -Scopes $escopos -UseDeviceAuthentication -NoWelcome
}
else {
    Connect-MgGraph -Scopes $escopos -NoWelcome
}

$upn = "$Usuario@$Dominio"
$logPath = "$PSScriptRoot\jml-log.csv"

# --- Funções auxiliares -------------------------------------------------------
function Write-Log {
    param([string]$AcaoLog, [string]$Detalhe)
    [pscustomobject]@{
        DataHora = (Get-Date -Format 's')
        Acao     = $AcaoLog
        Usuario  = $upn
        Detalhe  = $Detalhe
    } | Export-Csv -Path $logPath -Append -NoTypeInformation -Encoding UTF8
}

function New-SenhaTemporaria {
    $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $base = -join (1..12 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return $base + 'aB3!'
}

function Get-GrupoPorNome {
    param([string]$NomeGrupo)
    Get-MgGroup -Filter "displayName eq '$NomeGrupo'" | Select-Object -First 1
}

function Get-UsuarioPorUpn {
    param([string]$UpnBusca)
    Get-MgUser -Filter "userPrincipalName eq '$UpnBusca'" | Select-Object -First 1
}

function Get-Participacoes {
    param([string]$UserId)
    $itens = Get-MgUserMemberOf -UserId $UserId -All
    $grupos = @()
    $funcoes = @()
    foreach ($i in $itens) {
        $tipo = $i.AdditionalProperties['@odata.type']
        $nomeItem = $i.AdditionalProperties['displayName']
        if ($tipo -eq '#microsoft.graph.group') {
            $grupos += [pscustomobject]@{ Id = $i.Id; Nome = $nomeItem }
        }
        elseif ($tipo -eq '#microsoft.graph.directoryRole') {
            $funcoes += $nomeItem
        }
    }
    return @{ Grupos = $grupos; Funcoes = $funcoes }
}

function Remove-DosGrupos {
    param([string]$UserId, $Grupos, [string]$ManterGrupoId)
    $removidos = 0
    foreach ($g in $Grupos) {
        if ($g.Id -eq $ManterGrupoId) { continue }
        try {
            $null = Remove-MgGroupMemberByRef -GroupId $g.Id -DirectoryObjectId $UserId
            Write-Host "    [-] Removido do grupo: $($g.Nome)"
            $removidos++
        }
        catch {
            Write-Host "    [!] Não foi possível remover de $($g.Nome): $($_.Exception.Message)"
        }
    }
    return $removidos
}

# --- Ações --------------------------------------------------------------------
switch ($Acao) {

    'Joiner' {
        if (-not $Nome -or -not $Departamento -or -not $Grupo) {
            throw "Joiner exige -Nome, -Departamento e -Grupo."
        }
        if (Get-UsuarioPorUpn $upn) { throw "O usuário já existe: $upn" }

        $grupoDestino = Get-GrupoPorNome $Grupo
        if (-not $grupoDestino) { throw "Grupo não encontrado: $Grupo" }

        $senha = New-SenhaTemporaria
        $novo = New-MgUser `
            -DisplayName $Nome `
            -UserPrincipalName $upn `
            -MailNickname $Usuario `
            -Department $Departamento `
            -UsageLocation "BR" `
            -AccountEnabled `
            -PasswordProfile @{ Password = $senha; ForceChangePasswordNextSignIn = $true }

        New-MgGroupMember -GroupId $grupoDestino.Id -DirectoryObjectId $novo.Id

        [pscustomobject]@{ UPN = $upn; SenhaTemporaria = $senha } |
            Export-Csv -Path "$PSScriptRoot\senhas-temporarias.csv" -Append -NoTypeInformation -Encoding UTF8

        Write-Host "[+] JOINER: $upn criado no departamento $Departamento e adicionado a $Grupo"
        Write-Log 'Joiner' "Departamento $Departamento; grupo $Grupo"
    }

    'Mover' {
        if (-not $Departamento -or -not $Grupo) {
            throw "Mover exige -Departamento e -Grupo (destino)."
        }
        $u = Get-UsuarioPorUpn $upn
        if (-not $u) { throw "Usuário não encontrado: $upn" }

        $grupoDestino = Get-GrupoPorNome $Grupo
        if (-not $grupoDestino) { throw "Grupo não encontrado: $Grupo" }

        $info = Get-Participacoes $u.Id
        $removidos = Remove-DosGrupos -UserId $u.Id -Grupos $info.Grupos -ManterGrupoId $grupoDestino.Id

        if ($info.Grupos.Id -notcontains $grupoDestino.Id) {
            New-MgGroupMember -GroupId $grupoDestino.Id -DirectoryObjectId $u.Id
            Write-Host "    [+] Adicionado ao grupo: $Grupo"
        }

        Update-MgUser -UserId $u.Id -Department $Departamento

        Write-Host "[~] MOVER: $upn agora em $Departamento ($Grupo); $removidos grupo(s) antigo(s) removido(s)"
        if ($info.Funcoes.Count -gt 0) {
            Write-Host "[!] ATENÇÃO: funções administrativas ainda atribuídas (revisar manualmente): $($info.Funcoes -join ', ')"
        }
        Write-Log 'Mover' "Novo departamento $Departamento; grupo $Grupo; grupos removidos: $removidos"
    }

    'Leaver' {
        $u = Get-UsuarioPorUpn $upn
        if (-not $u) { throw "Usuário não encontrado: $upn" }

        $info = Get-Participacoes $u.Id

        Update-MgUser -UserId $u.Id -AccountEnabled:$false
        Write-Host "    [-] Conta desativada"

        try {
            # Chamada REST direta: evita um erro de formatação do cmdlet Revoke-MgUserSignInSession no Windows PowerShell 5.1
            $null = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$($u.Id)/revokeSignInSessions"
            Write-Host "    [-] Sessões ativas revogadas"
        }
        catch {
            Write-Host "    [!] Não foi possível revogar as sessões: $($_.Exception.Message)"
        }

        $removidos = Remove-DosGrupos -UserId $u.Id -Grupos $info.Grupos -ManterGrupoId ''

        Write-Host "[x] LEAVER: $upn desativado; $removidos grupo(s) removido(s). A conta foi mantida para auditoria."
        if ($info.Funcoes.Count -gt 0) {
            Write-Host "[!] ATENÇÃO: funções administrativas ainda atribuídas (revisar manualmente): $($info.Funcoes -join ', ')"
        }
        Write-Log 'Leaver' "Conta desativada; sessões revogadas; grupos removidos: $removidos"
    }
}

Disconnect-MgGraph | Out-Null
Write-Host "Concluído."
