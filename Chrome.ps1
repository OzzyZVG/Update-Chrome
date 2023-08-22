$computers = Get-Content "\\BR01S-FS\Resources\Scripts\Chrome\computer_list.txt"
$chromeVersion = "116.0.5845.97"
$installerUrl = "https://dl.google.com/tag/s/appguid%3D%7B8A69D345-D564-463C-AFF1-A69D9E530F96%7D%26iid%3D%7BC3100B2C-74F3-F78D-8A8D-CECBE8DDF694%7D%26lang%3Dpt-BR%26browser%3D5%26usagestats%3D1%26appname%3DGoogle%2520Chrome%26needsadmin%3Dprefers%26ap%3Dx64-stable-statsdef_1%26installdataindex%3Dempty/update2/installers/ChromeSetup.exe"
$installerPath = "C:\Temp\ChromeSetup.exe"

foreach ($computer in $computers) {
    Write-Output "Verificando se a máquina $computer está online"
    if (Test-Connection -ComputerName $computer -Count 1 -Quiet) {
        Write-Output "Máquina online, acessando via hostname"
        $pssession = New-PSSession -ComputerName $computer -ErrorAction SilentlyContinue
        if ($null -eq $pssession) {
            Write-Output "Acesso via hostname falhou, tentando via IP"
            $ip = Test-Connection -ComputerName $computer -Count 1 | Select-Object -ExpandProperty Address
            $pssession = New-PSSession -ComputerName $ip -ErrorAction SilentlyContinue
        }
        if ($null -eq $pssession) {
            Write-Output "Falha ao acessar a máquina $computer"
            continue
        }

        # Verificar versão do Chrome
        $remoteChromeVersion = Invoke-Command -Session $pssession -ScriptBlock {
            (Get-Item (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe').'(Default)').VersionInfo.ProductVersion
        }
        if ($remoteChromeVersion -eq $chromeVersion) {
            Write-Output "Chrome já está atualizado na máquina $computer"
            Remove-PSSession -Session $pssession
            continue
        }

        # Baixar o instalador se não existir
        if (!(Invoke-Command -Session $pssession -ScriptBlock { Test-Path $using:installerPath })) {
            Write-Output "Baixando o instalador do Chrome na máquina $computer"
            Invoke-Command -Session $pssession -ScriptBlock {
                Invoke-WebRequest -Uri $using:installerUrl -OutFile $using:installerPath
            }
        }

        # Instalar o Chrome
        Write-Output "Instalando o Chrome..."
        $installResult = Invoke-Command -Session $pssession -ScriptBlock {
            $process = Start-Process -FilePath $using:installerPath -ArgumentList "/silent /install" -PassThru
            $process.WaitForExit(180000) # Esperar no máximo 3 minutos
            $process.ExitCode
        }
        if ($null -eq $installResult -or $installResult -ne 0) {
            Write-Output "Falha ao atualizar o Chrome na máquina $computer"
        } else {
            Write-Output "Chrome instalado com sucesso"
            # Execute o comando remoto a partir da raiz do executável usando Invoke-Command dentro da sessão remota
            Write-Output "Executando o comando no host $computer ..."
            Invoke-Command -Session $pssession -ScriptBlock {
                Set-Location "C:\Program Files\tenable\nessus agent"
                & ".\nessuscli.exe" scan-triggers --start --uuid=091d168d-0109-45a3-8ae9-845a8aaa4f47
            }
        }
        Remove-PSSession -Session $pssession
    } else {
        Write-Output "Máquina $computer está offline"
    }
}