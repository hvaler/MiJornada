# Diseno de stages — Patron canonico del ecosistema

> Estructura completa Build + DeployDev + DeployDemo + DeployProd validada en 2 pilotos (BiPublisher.Api + MyCompany.Claude.Guia).

## Arquitectura general

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Pool BUILDERS (collection-level, server-wide, ya autorizado)             │
│                                                                          │
│   LADYADA_AGENTE1, LADYADA_AGENTE2 (computer LADYADA)                    │
│      Agent.ComputerName = LADYADA       → builds                         │
│                                                                          │
│   <SERVER>_DEPLOY (uno por server destino)                               │
│      DeployTarget = <env>               → deploys                        │
└──────────────────────────────────────────────────────────────────────────┘

Stages generados:
  Build       (CI auto)  → demand Agent.ComputerName=LADYADA
  DeployDev   (CD auto)  → demand DeployTarget=dev
  DeployDemo  (CD manual: gate ManualValidation@0) → DeployTarget=demowww
  DeployProd  (CD manual: gate Environment+group)  → DeployTarget=produccion
                                                     2 jobs serie (A, B)
                                                     con backup + rollback condicional
```

## Stage Build — patron canonico (.NET)

```yaml
- stage: Build
  displayName: 'Build & Test'
  jobs:
    - job: BuildAndTest
      pool:
        name: BUILDERS                                    # R1
        demands:
          - Agent.ComputerName -equals LADYADA            # R1
      timeoutInMinutes: 30
      steps:
        # R16: fail-fast secretos si hay VG
        - task: PowerShell@2
          displayName: 'Fail-fast: validar VG secretos'
          condition: succeeded()
          inputs:
            targetType: inline
            script: |
              # [R2: bloque TLS 1.2+]
              $required = @('<NombreSecreto1>', '<NombreSecreto2>')
              # ... validacion fail-fast

        # R12 warning-only: linter anti-patterns
        - task: PowerShell@2
          displayName: 'Linter anti-patterns (warning-only)'
          continueOnError: true
          inputs: { ... }

        # R4: tasks canonicas
        - task: UseDotNet@2
          displayName: 'Install .NET SDK'
          inputs:
            packageType: 'sdk'
            version: '10.0.x'

        - task: DotNetCoreCLI@2
          displayName: 'dotnet restore'
          inputs:
            command: 'restore'
            projects: '<SLN_PATH>'

        - task: DotNetCoreCLI@2
          displayName: 'dotnet build'
          inputs:
            command: 'build'
            projects: '<SLN_PATH>'
            arguments: '--configuration Release --no-restore'

        - task: DotNetCoreCLI@2
          displayName: 'dotnet test (coverage)'
          inputs:
            command: 'test'
            projects: '<TESTS_CSPROJ>'
            arguments: '--configuration Release --no-build --collect:"XPlat Code Coverage" --settings coverlet.runsettings'

        # R4: @1 (NO @2)
        - task: PublishCodeCoverageResults@1
          displayName: 'Publish code coverage'
          inputs:
            codeCoverageTool: 'Cobertura'
            summaryFileLocation: '$(Agent.TempDirectory)/**/*cobertura.xml'

        # R18: Coverage gate (mira summary, WARN-first). Mira 0.8.1 gatea por % cobertura, NO CRAP.
        - task: PowerShell@2
          displayName: 'Coverage gate line>=70/branch>=60 (R18, WARN)'
          inputs:
            targetType: inline
            script: |
              $env:PATH = "$env:PATH;$(Join-Path $env:USERPROFILE '.dotnet\tools')"   # invocar 'mira', NO 'dotnet mira'
              $xml = Get-ChildItem $env:AGENT_TEMPDIRECTORY -Recurse -Filter '*cobertura.xml' | Select-Object -First 1 -ExpandProperty FullName
              & mira summary -i "$xml" --threshold-line 70 --threshold-branch 60   # exit 3 si < umbral
              if ($LASTEXITCODE -ne 0) { Write-Warning "R18: cobertura < umbral -> AVISO (WARN-first, no bloquea)" }
              exit 0

        - task: DotNetCoreCLI@2
          displayName: 'dotnet publish'
          inputs:
            command: 'publish'
            projects: '<API_CSPROJ>'
            arguments: '--configuration Release --no-build --output $(Build.ArtifactStagingDirectory) /p:GenerateBuildInfoConfigFile=false'

        - task: PublishBuildArtifacts@1
          displayName: 'Publish artifact drop'
          inputs:
            PathtoPublish: '$(Build.ArtifactStagingDirectory)'
            ArtifactName: 'drop'
```

## Stage DeployDev — auto, sin gate

```yaml
- stage: DeployDev
  displayName: 'Deploy a DEV (auto)'
  dependsOn: Build
  condition: succeeded()
  jobs:
    - job: DeployToDev
      pool:
        name: BUILDERS
        demands:
          - DeployTarget -equals dev                       # R1
      timeoutInMinutes: 15
      steps:
        - checkout: none                                   # R8
        - task: PowerShell@2
          displayName: 'Descargar artefacto (REST API)'    # R3
          env:
            SYSTEM_ACCESSTOKEN: $(System.AccessToken)
          inputs:
            targetType: inline
            script: |
              # [R2: bloque TLS 1.2+]
              $headers = @{ Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN" }
              $apiBase = '$(System.CollectionUri)$(System.TeamProject)/_apis/build/builds/$(Build.BuildId)'
              $artifactInfo = Invoke-RestMethod -Uri "$apiBase/artifacts?artifactName=drop&api-version=5.0" -Headers $headers
              $downloadUrl = $artifactInfo.resource.downloadUrl
              $zipPath = "$env:AGENT_TEMPDIRECTORY\artifact.zip"
              Invoke-WebRequest -Uri $downloadUrl -Headers $headers -OutFile $zipPath
              Expand-Archive -Path $zipPath -DestinationPath '$(Pipeline.Workspace)' -Force
              $package = Get-ChildItem '$(Pipeline.Workspace)/drop' -Filter '*.zip' | Select-Object -First 1
              Write-Host "##vso[task.setvariable variable=MsDeployPackage]$($package.FullName)"

        - task: IISWebAppDeploymentOnMachineGroup@0         # R4
          inputs:
            WebSiteName: 'Default Web Site'
            VirtualApplication: '<REPO_KEBAB>'
            Package: '$(MsDeployPackage)'
            RemoveAdditionalFilesFlag: true
            TakeAppOfflineFlag: <true|false>                # R10 segun stack
```

## Stage DeployDemo — manual gate ManualValidation@0

```yaml
- stage: DeployDemo
  displayName: 'Deploy a DEMO (manual gate)'
  dependsOn: Build
  condition: succeeded()
  jobs:
    - job: WaitForApproval
      pool: server                                          # server job, NO agent
      timeoutInMinutes: 1440
      steps:
        - task: ManualValidation@0
          inputs:
            notifyUsers: '<APPROVER_EMAIL>'
            instructions: 'Aprobar deploy a DEMO del build $(Build.BuildNumber).'
            onTimeout: 'reject'

    - job: DeployToDemo
      dependsOn: WaitForApproval
      condition: succeeded()
      pool:
        name: BUILDERS
        demands:
          - DeployTarget -equals demowww
      timeoutInMinutes: 30
      steps:
        - checkout: none
        # [Descarga REST API igual que DEV]
        # [Backup pre-deploy R15 capa 1]
        # [IISWebAppDeploymentOnMachineGroup@0 con AdditionalArguments enableRule R15 capa 2]
        # [Smoke best-effort SPA o estricto .NET]
        # [Rollback condition: failed() R15 capa 3]
```

## Stage DeployProd — Environment + group approval + 2 servers rolling

```yaml
- stage: DeployProd
  displayName: 'Deploy a PROD (manual, 2 servers rolling)'
  dependsOn: DeployDemo
  condition: succeeded()
  jobs:
    - deployment: DeployToProd_A                            # primer server, con gate
      environment: '<PROYECTO>-Prod'                        # approval check del grupo
      pool:
        name: BUILDERS
        demands:
          - Agent.Name -equals STRIFY01_DEPLOY
      timeoutInMinutes: 30
      strategy:
        runOnce:
          deploy:
            steps:
              - download: none                              # equivalente checkout: none
              # [Descarga REST API + Backup + MSDeploy + Smoke + Rollback condicional]

    - job: DeployToProd_B                                   # segundo server, sin gate
      dependsOn: DeployToProd_A
      condition: succeeded()
      pool:
        name: BUILDERS
        demands:
          - Agent.Name -equals STRIFY02_DEPLOY
      timeoutInMinutes: 30
      steps:
        - checkout: none
        # [Mismos steps que DeployToProd_A, sin gate]
```

## Stage Build — variante Vue+Vite+TS

```yaml
- stage: Build
  jobs:
    - job: BuildAndTest
      pool:
        name: BUILDERS
        demands:
          - Agent.ComputerName -equals LADYADA
      steps:
        - task: NodeTool@0
          displayName: 'Install Node.js'
          inputs:
            versionSpec: '22.x'                              # Node 22 LTS default

        - script: npm ci
          displayName: 'npm ci'
          workingDirectory: '03_Desarrollo'

        - script: npx vue-tsc --noEmit
          displayName: 'Type check (vue-tsc)'
          workingDirectory: '03_Desarrollo'

        - script: npm run lint
          displayName: 'Lint'
          workingDirectory: '03_Desarrollo'
          continueOnError: true                              # informativo

        - script: npx vitest run --coverage
          displayName: 'Tests + coverage'
          workingDirectory: '03_Desarrollo'

        # R4: @1 con Cobertura desde Vitest
        - task: PublishCodeCoverageResults@1
          inputs:
            codeCoverageTool: 'Cobertura'
            summaryFileLocation: '03_Desarrollo/coverage/cobertura-coverage.xml'

        - script: npm run build
          displayName: 'Vite build'
          workingDirectory: '03_Desarrollo'

        - task: ArchiveFiles@2
          displayName: 'Zip dist/'
          inputs:
            rootFolderOrFile: '03_Desarrollo/dist'
            includeRootFolder: false
            archiveType: 'zip'
            archiveFile: '$(Build.ArtifactStagingDirectory)/<APP_NAME>.zip'

        - task: PublishBuildArtifacts@1
          inputs:
            PathtoPublish: '$(Build.ArtifactStagingDirectory)'
            ArtifactName: 'drop'
```

## Variables comunes

```yaml
variables:
  - group: <PIPELINE_NAME>-secrets                          # R16, si VG
  - name: BuildConfiguration
    value: 'Release'
  # Solo .NET:
  - name: solutionPath
    value: '<SLN_PATH>'
  - name: apiProject
    value: '<API_CSPROJ>'
  - name: testProject
    value: '<TESTS_CSPROJ>'
  - name: coverletSettings
    value: '04_Pruebas/coverlet.runsettings'
  - name: coverageLineThreshold
    value: '70'
  - name: coverageBranchThreshold
    value: '60'
  - name: coverageCrapThreshold
    value: '30'
```

## Trigger canonico

```yaml
trigger:
  branches:
    include:
      - <RAMA_BASE>                                          # main / master / dev.<usuario>
  paths:
    # R7: workaround TFS 2020 — emitir AMBOS patrones
    include:
      - '03_Desarrollo/**'
      - '03_Desarrollo/**/*'
      - '04_Pruebas/**'
      - '04_Pruebas/**/*'
      - 'azure-pipelines.yml'

pr: none                                                     # PR triggers gestionados por branch policy
```

---

*Diseno de stages v3.11.0 — Validado en 2 pilotos (DT-004 BiPublisher.Api + MyCompany.Claude.Guia)*
