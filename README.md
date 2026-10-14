# Lab de IAM com Microsoft Entra ID

Laboratório prático de **Identity & Access Management (IAM)** em um tenant do Microsoft Entra ID, com foco em quatro práticas da gestão de acessos: **provisionamento por script**, **menor privilégio (RBAC)**, **ciclo de vida de identidades (Joiner / Mover / Leaver)** e **autenticação (MFA e OAuth 2.0 / OpenID Connect)**.

Todos os usuários e dados usados aqui são fictícios.

📄 **Relatório completo, com todos os prints de cada etapa:** [`relatorio/Relatorio_IAM_Entra_ID.pdf`](relatorio/Relatorio_IAM_Entra_ID.pdf)

## O que foi feito

| Etapa | O que mostra | Como |
|---|---|---|
| 1. Usuários e grupos | Provisionamento em lote, sem cliques repetitivos | Script PowerShell (Microsoft Graph) lendo um CSV |
| 2. RBAC com menor privilégio | Cada perfil recebe só a função de que precisa | Atribuição de funções internas do Entra ID |
| 3. Joiner / Mover / Leaver | Entrada, mudança de área e saída de um usuário | Script PowerShell com registro em log |
| 4. MFA e OAuth 2.0 / OpenID Connect | Registro de MFA e leitura de um token de ID | Microsoft Authenticator e registro de aplicativo no Entra ID |

## Ambiente

- Tenant do Microsoft Entra ID (licença gratuita)
- VM Windows com Windows PowerShell 5.1
- Módulos Microsoft Graph PowerShell: `Authentication`, `Users` e `Groups`

## Estrutura do repositório

```
Entra-ID-iam-lab/
├── README.md
├── .gitignore
├── scripts/
│   ├── 01-criar-usuarios-grupos.ps1
│   ├── 02-jml.ps1
│   └── usuarios.csv
└── relatorio/
    └── Relatorio_IAM_Entra_ID.pdf   (relatório completo, com os prints de cada etapa)
```

## Etapa 1 — Usuários e grupos por script

O script `01-criar-usuarios-grupos.ps1` lê o `usuarios.csv` (nome, usuário, departamento e grupo) e:

- cria cada usuário que ainda não existe, com **senha temporária aleatória** e **troca obrigatória no primeiro login**;
- define o **local de uso** (necessário para atribuir licenças depois);
- cria os grupos de segurança `GRP-TI`, `GRP-Financeiro` e `GRP-Auditoria` e adiciona cada usuário ao seu grupo;
- pode ser executado várias vezes sem duplicar nada (idempotente).

```powershell
cd scripts
.\01-criar-usuarios-grupos.ps1 -Dominio "seudominio.onmicrosoft.com"
```

## Etapa 2 — RBAC com menor privilégio

| Perfil | Usuário | Função no Entra ID | O que pode | O que não pode |
|---|---|---|---|---|
| TI (gestão de usuários) | ana.ti | Administrador de Usuários | Criar e gerenciar usuários e grupos | Alterar configurações do tenant |
| TI (suporte) | bruno.ti | Administrador de Senhas | Redefinir senhas de usuários comuns | Criar ou excluir usuários |
| Auditoria | elisa.aud | Leitor Global | Consultar configurações e dados do diretório | Alterar qualquer coisa |
| Financeiro e Auditoria | carla.fin, diego.fin, fabio.aud | Nenhuma função administrativa | Usar os próprios acessos | Qualquer ação administrativa |
| Conta de administração | admin-trial | Administrador Global (único) | Administrar o tenant | — |

**Critério:** cada função foi escolhida pelo menor conjunto de permissões que cumpre a tarefa do perfil, e só uma conta tem o poder máximo.

## Etapa 3 — Ciclo de vida: Joiner, Mover e Leaver

O script `02-jml.ps1` executa as três ações e registra cada uma no `jml-log.csv` (data e hora, ação, usuário e detalhe).

| Ação | O que o script faz |
|---|---|
| **Joiner** | Cria o usuário, define o departamento e o adiciona ao grupo da área |
| **Mover** | Atualiza o departamento, remove o usuário dos grupos antigos e o adiciona ao grupo novo. Avisa se ainda houver funções administrativas atribuídas |
| **Leaver** | Desativa a conta, revoga as sessões ativas e remove o usuário de todos os grupos. **A conta não é excluída**, para manter a trilha de auditoria |

```powershell
.\02-jml.ps1 -Acao Joiner -Dominio "seudominio.onmicrosoft.com" -Usuario gabriel.ti -Nome "Gabriel (TI)" -Departamento TI -Grupo GRP-TI
.\02-jml.ps1 -Acao Mover  -Dominio "seudominio.onmicrosoft.com" -Usuario gabriel.ti -Departamento Financeiro -Grupo GRP-Financeiro
.\02-jml.ps1 -Acao Leaver -Dominio "seudominio.onmicrosoft.com" -Usuario gabriel.ti
```

Na mudança de área, o acesso antigo é removido para evitar **acúmulo de privilégios**.

## Etapa 4 — MFA e OAuth 2.0 / OpenID Connect

Duas práticas de autenticação no tenant gratuito.

**MFA com Microsoft Authenticator.** O usuário `bruno.ti`, que tem a função de Administrador de Senhas, registrou a autenticação multifator no primeiro login, com o aplicativo Microsoft Authenticator. A evidência está nos métodos de autenticação do usuário e nos detalhes da autenticação do log de entrada, no [relatório](relatorio/Relatorio_IAM_Entra_ID.pdf).

**Aplicativo com OAuth 2.0 e OpenID Connect.** Foi registrado o aplicativo `lab-iam-oidc` (locatário único), com o URI de redirecionamento `https://jwt.ms`, site da Microsoft que decodifica tokens. Uma requisição ao endpoint de autorização do tenant devolveu um **token de ID** depois do login do `bruno.ti`:

```
https://login.microsoftonline.com/<ID-DO-DIRETORIO>/oauth2/v2.0/authorize?client_id=<ID-DO-APLICATIVO>&response_type=id_token&redirect_uri=https%3A%2F%2Fjwt.ms&scope=openid%20profile%20email&response_mode=fragment&nonce=1234
```

No token decodificado foram analisados os campos `iss` (emissor), `aud` (o aplicativo), `tid` (o locatário), `name` e `preferred_username` (o usuário), `iat` e `exp` (emissão e validade) e `ver` (versão 2.0). O documento de metadados do OpenID Connect do tenant mostra os endpoints de autorização e de token, o emissor e as chaves de assinatura.

Observações:
- O token de ID deste teste **não trouxe o campo `amr`**, então a prova do MFA vem do log de entrada, e não do token.
- O recebimento de tokens de ID (fluxo implícito, considerado legado) foi habilitado só para o teste e **desabilitado em seguida**.
- Não foram usados SAML, LDAP, SSO corporativo nem ferramentas de PAM. Esta etapa cobre MFA e os conceitos de OAuth 2.0 e OpenID Connect na prática.

## Decisões de segurança

- Nenhuma senha é escrita no código nem no CSV de entrada. As senhas temporárias são aleatórias e vão para um arquivo local (`senhas-temporarias.csv`), **excluído do repositório pelo `.gitignore`**.
- Troca de senha obrigatória no primeiro login.
- Funções administrativas atribuídas por necessidade, com um único Administrador Global.
- Saída de usuário: conta desativada e sessões revogadas, sem exclusão imediata.
- MFA com Microsoft Authenticator em conta com função administrativa.
- Fluxo implícito do aplicativo de teste habilitado só para gerar o token e desabilitado depois.

## Problemas encontrados e como foram resolvidos

- **Instalação do módulo parada:** o instalador do NuGet tentava instalar para todos os usuários e exigia administrador. Resolvido com `-Scope CurrentUser`.
- **Erro `AADSTS70008` (token expirado) no login:** apareceu na janela de login do Windows (WAM). Passei a usar o login pelo navegador e deixei o login por código de dispositivo como opção (`-CodigoDeDispositivo`).
- **Erro de runspace ao revogar sessões:** o cmdlet tipado falhou no Windows PowerShell 5.1. Troquei por uma chamada direta à API do Graph.
- **Acentos quebrados no terminal:** o Windows PowerShell 5.1 lê o script com a codificação errada. Resolvido salvando os arquivos em UTF-8 com BOM.

## Próximos passos

- **PIM (Privileged Identity Management):** tornar a função de administrador elegível e temporária, com justificativa e MFA. Exige a licença Entra ID P2.
- **Conditional Access:** exigir MFA para funções administrativas.
- **Revisão de acessos** periódica dos grupos e das funções.

## Autor

Leonardo Garcia Santos — [LinkedIn](https://www.linkedin.com/in/leonardo-garcia-santos-a81a5a1b4) | [GitHub](https://github.com/leonardogsantos)
