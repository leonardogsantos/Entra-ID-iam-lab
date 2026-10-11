# Lab de IAM com Microsoft Entra ID

Laboratório prático de **Identity & Access Management (IAM)** em um tenant do Microsoft Entra ID, com foco em três práticas centrais da gestão de acessos: **provisionamento por script**, **menor privilégio (RBAC)** e **ciclo de vida de identidades (Joiner / Mover / Leaver)**.

Todos os usuários e dados usados aqui são fictícios.

## O que foi feito

| Etapa | O que mostra | Como |
|---|---|---|
| 1. Usuários e grupos | Provisionamento em lote, sem cliques repetitivos | Script PowerShell (Microsoft Graph) lendo um CSV |
| 2. RBAC com menor privilégio | Cada perfil recebe só a função de que precisa | Atribuição de funções internas do Entra ID |
| 3. Joiner / Mover / Leaver | Entrada, mudança de área e saída de um usuário | Script PowerShell com registro em log |

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

## Decisões de segurança

- Nenhuma senha é escrita no código nem no CSV de entrada. As senhas temporárias são aleatórias e vão para um arquivo local (`senhas-temporarias.csv`), **excluído do repositório pelo `.gitignore`**.
- Troca de senha obrigatória no primeiro login.
- Funções administrativas atribuídas por necessidade, com um único Administrador Global.
- Saída de usuário: conta desativada e sessões revogadas, sem exclusão imediata.

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
