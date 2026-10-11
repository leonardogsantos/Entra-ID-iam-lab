<#
.SYNOPSIS
    Lab de IAM (Microsoft Entra ID) - Etapa 1: criação de usuários e grupos a partir de um CSV.

.DESCRIPTION
    - Lê usuarios.csv (Nome, Usuario, Departamento, Grupo)
    - Cria os usuários que ainda não existem, com senha temporária aleatória
      e troca de senha obrigatória no primeiro login
    - Cria os grupos de segurança e adiciona cada usuário ao seu grupo
    - É idempotente: pode ser executado mais de uma vez sem duplicar nada
    - Salva as senhas temporárias em senhas-temporarias.csv (NÃO versionar no Git)

.EXAMPLE
    .\01-criar-usuarios-grupos.ps1 -Dominio "seudominio.onmicrosoft.com"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Dominio,

    [switch]$CodigoDeDispositivo,

    [string]$CsvPath = "$PSScriptRoot\usuarios.csv",
    [string]$SaidaSenhas = "$PSScriptRoot\senhas-temporarias.csv"
)

# --- Módulo Microsoft Graph -------------------------------------------------
$modulosNecessarios = 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Groups'
foreach ($modulo in $modulosNecessarios) {
    if (-not (Get-Module -ListAvailable -Name $modulo)) {
        Write-Host "Instalando o módulo $modulo ..."
        Install-Module $modulo -Scope CurrentUser -Force
    }
}

# Login: por padrão abre o navegador; com -CodigoDeDispositivo usa o código em microsoft.com/devicelogin
# (útil quando a janela de login do Windows falha, por exemplo com o erro AADSTS70008)
if ($CodigoDeDispositivo) {
    Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All" -UseDeviceAuthentication -NoWelcome
}
else {
    Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All" -NoWelcome
}

# --- Senha temporária aleatória (com complexidade garantida) -----------------
function New-SenhaTemporaria {
    $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $base = -join (1..12 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return $base + 'aB3!'
}

$usuarios = Import-Csv -Path $CsvPath -Encoding UTF8
$senhasGeradas = @()

# --- Usuários ---------------------------------------------------------------
foreach ($u in $usuarios) {
    $upn = "$($u.Usuario)@$Dominio"
    $existente = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue

    if ($existente) {
        Write-Host "[=] Já existe: $upn"
        continue
    }

    $senha = New-SenhaTemporaria
    New-MgUser `
        -DisplayName $u.Nome `
        -UserPrincipalName $upn `
        -MailNickname $u.Usuario `
        -Department $u.Departamento `
        -UsageLocation "BR" `
        -AccountEnabled `
        -PasswordProfile @{ Password = $senha; ForceChangePasswordNextSignIn = $true } | Out-Null

    $senhasGeradas += [pscustomobject]@{ UPN = $upn; SenhaTemporaria = $senha }
    Write-Host "[+] Usuário criado: $upn"
}

# --- Grupos e participação --------------------------------------------------
$nomesGrupos = $usuarios | Select-Object -ExpandProperty Grupo | Sort-Object -Unique

foreach ($nomeGrupo in $nomesGrupos) {
    $grupo = Get-MgGroup -Filter "displayName eq '$nomeGrupo'" | Select-Object -First 1

    if (-not $grupo) {
        $apelido = $nomeGrupo -replace '[^a-zA-Z0-9]', ''
        $grupo = New-MgGroup `
            -DisplayName $nomeGrupo `
            -MailEnabled:$false `
            -MailNickname $apelido `
            -SecurityEnabled:$true
        Write-Host "[+] Grupo criado: $nomeGrupo"
    }
    else {
        Write-Host "[=] Grupo já existe: $nomeGrupo"
    }

    $membrosDoGrupo = $usuarios | Where-Object { $_.Grupo -eq $nomeGrupo }
    foreach ($m in $membrosDoGrupo) {
        $upn = "$($m.Usuario)@$Dominio"
        $mgUser = Get-MgUser -Filter "userPrincipalName eq '$upn'"
        try {
            New-MgGroupMember -GroupId $grupo.Id -DirectoryObjectId $mgUser.Id -ErrorAction Stop
            Write-Host "    [+] $upn adicionado a $nomeGrupo"
        }
        catch {
            Write-Host "    [=] $upn já é membro de $nomeGrupo (ou não pôde ser adicionado)"
        }
    }
}

# --- Senhas temporárias -----------------------------------------------------
if ($senhasGeradas.Count -gt 0) {
    $senhasGeradas | Export-Csv -Path $SaidaSenhas -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Host "Senhas temporárias salvas em: $SaidaSenhas"
    Write-Host "ATENÇÃO: não suba esse arquivo para o GitHub (adicione ao .gitignore)."
}

Disconnect-MgGraph | Out-Null
Write-Host "Concluído."
