function parseExeUninstall
{

    param (
        [string]$exeString
    )

    $pattern = ' +(?=(?:[^\"]*\"[^\"]*\")*[^\"]*$)'
    $exeString = $exeString.Trim()

    ## Unquoted path containing spaces (e.g. HP: c:\Program Files\HP\...\setup.exe), take everything up to the first .exe as the executable
    if (($exeString -notmatch '^"') -and ($exeString -match '^(?<exe>[^"]+?\.exe)(?:\s+(?<args>.*))?$'))
    {
        $exeArgs = @()
        if ($matches['args'])
        {
            $exeArgs = $matches['args'].Trim() -split $pattern
        }
        return @($matches['exe']) + $exeArgs
    }
    $exeString = $exeString.Trim()

    ## Unquoted path containing spaces (e.g. HP: c:\Program Files\HP\...\setup.exe), take everything up to the first .exe as the executable
    if (($exeString -notmatch '^"') -and ($exeString -match '^(?<exe>[^"]+?\.exe)(?:\s+(?<args>.*))?$'))
    {
        $exeArgs = @()
        if ($matches['args'])
        {
            $exeArgs = $matches['args'].Trim() -split $pattern
        }
        return @($matches['exe']) + $exeArgs
    }

    return $exeString -split $pattern
}

function UninstallAppFull
{

    param (
        [string]$appName
    )

    # Get a list of installed applications from Programs and Features
    $installedApps = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*,
    HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Where-Object { $null -ne $_.DisplayName } |
        Select-Object DisplayName, UninstallString, QuietUninstallString

    if ( [System.Security.Principal.WindowsIdentity]::GetCurrent().Name -ne 'NT AUTHORITY\SYSTEM')
    {
        $userInstalledApps = Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
            Where-Object { $null -ne $_.DisplayName } |
            Select-Object DisplayName, UninstallString, QuietUninstallString
    }

    # Wrapping the two arrays in @( ) forces them to resolve as arrays, including if they're NULL (such as if running in the system context and $userInstalledApps wasn't initialized above).
    $allInstalledApps = @($installedApps) + @($userInstalledApps) | Where-Object { $_.DisplayName -eq "$appName" }

    # Loop through the list of installed applications and uninstall them
    foreach ($app in $allInstalledApps)
    {

        $uninstallString = $app.UninstallString
        $displayName = $app.DisplayName

        Write-Output "Calling Uninstaller for: $displayName"
        if ($uninstallString -match "^\s*(C:\\Windows\\System32\\)?msiexec(\.exe)?\s+\S*")
        {
            Write-Output "MSI Uninstall detected"
            #MSI install, replace the I with an X and make it quiet

            $uninstallString -match '(?<content>{.*})' | Out-Null
            $GUID = $matches['content']
            $uninstallArgs = @(
                '/X',
                $GUID,
                '/quiet',
                '/norestart',
                '/qn'
            )
            $uninstaller = "msiexec.exe"

            Write-Output "Uninstall Arguments: $uninstallArgs"

            try
            {
                $proc = Start-Process $uninstaller -ArgumentList $uninstallArgs -wait -PassThru
                Write-Output "MSI Uninstaller for $displayName exited with code: $($proc.ExitCode)"
            } catch
            {
                Write-Output "Failed to call MSI Uninstaller for: $displayName"
                Write-Output "UninstallArgs: $uninstallArgs"
                Write-Output "Error thrown: $($_.Exception.Message)"
            }
        } else
        {
            Write-Output "EXE Uninstall detected"
            #Exe installer, run straight path
            ##Prefer QuietUninstallString when the app registers one
            $exeString = $uninstallString
            if ($app.QuietUninstallString)
            {
                $exeString = $app.QuietUninstallString
                Write-Output "QuietUninstallString found, using it instead"
            }
            Write-Output "Retrieved Uninstall String: $exeString"
            $parsedString = @(parseExeUninstall -exeString $exeString)
            $uninstallArgs = @($parsedString | Select-Object -Skip 1)
            $uninstaller = $parsedString[0].Trim('"')

            if (-not $app.QuietUninstallString)
            {
                if (($uninstallArgs -match '/uninstall') -and -not ($uninstallArgs -match '/quiet'))
                {
                    $uninstallArgs += '/quiet'
                } elseif ($uninstaller -match 'SupportAssistUninstaller\.exe$')
                {
                    if ($uninstallArgs -notcontains '/arp')
                    {
                        $uninstallArgs += '/arp'
                    }
                    $uninstallArgs += @('/S', '/v/qn')
                } elseif (($uninstaller -match '(uninst|uninstall)\.exe$') -and ($uninstallArgs -notcontains '/S'))
                {
                    $uninstallArgs += '/S'
                }
            }

            try
            {
                $exeStartParams = @{ FilePath = $uninstaller; Wait = $true; PassThru = $true }
                if ($uninstallArgs.Count -gt 0)
                {
                    $exeStartParams['ArgumentList'] = $uninstallArgs
                }
                $proc = Start-Process @exeStartParams
                Write-Output "EXE Uninstaller for $displayName exited with code: $($proc.ExitCode)"
            } catch
            {
                Write-Output "Failed to call EXE Uninstaller for: $displayName"
                Write-Output "Uninstaller: $uninstaller"
                Write-Output "UninstallArgs: $uninstallArgs"
                Write-Output "Error thrown: $($_.Exception.Message)"
            }
        }
    }
}

############################################################################################################
#                                        Remove Manufacturer Bloat                                         #
############################################################################################################

##Check Manufacturer
write-output "Detecting Manufacturer"
$details = Get-CimInstance -ClassName Win32_ComputerSystem
$manufacturer = $details.Manufacturer

if ($manufacturer -like "*HP*")
{
    write-output "HP detected"
    #Remove HP bloat

    ##HP Specific
    $UninstallPrograms = @(
        "Poly Lens"
        "HP Client Security Manager"
        "HP Notifications"
        "HP Security Update Service"
        "HP System Default Settings"
        "HP Wolf Security"
        "HP Wolf Security - Console"
        "HP Wolf Security Application Support for Sure Sense"
        "HP Wolf Security Application Support for Windows"
        "HP Wolf Security Application Support for Chrome 122.0.6261.139"
        "AD2F1837.HPPCHardwareDiagnosticsWindows"
        "AD2F1837.HPPowerManager"
        "AD2F1837.HPPrivacySettings"
        "AD2F1837.HPQuickDrop"
        "AD2F1837.HPSupportAssistant"
        "AD2F1837.HPSystemInformation"
        "AD2F1837.11510256BE195"
        "AD2F1837.HPAIExperienceCenter"
        "AD2F1837.HPDisplayCenter"
        "AD2F1837.HPInc.EnergyStar"
        "AD2F1837.HPPrinterControl"
        "AD2F1837.HPSystemEventUtility"
        "AD2F1837.myHP"
        "AD2F1837.OMENCommandCenter"
        "HP One Agent"
        "RealtekSemiconductorCorp.HPAudioControl",
        "HP Sure Recover",
        "HP Sure Run Module"
        "RealtekSemiconductorCorp.HPAudioControl_2.39.280.0_x64__dt26b99r8h8gj"
        "Windows Driver Package - HP Inc. sselam_4_4_2_453 AntiVirus  (11/01/2022 4.4.2.453)"
        "HP Insights"
        "HP Insights Analytics"
        "HP Insights Analytics Service"
        "HP Insights Analytics - Dependencies"
        "HP Performance Advisor"
        "HP Presence Video"
        "HP Audio Control"
        "HP Documentation"
        "AD2F1837.HPAudioControl"
        "HP Connection Optimizer"
    )

    $UninstallPrograms = $UninstallPrograms | Where-Object { $appstoignore -notcontains $_ }

    #$HPidentifier = "AD2F1837"

    #$ProvisionedPackages = Get-AppxProvisionedPackage -Online | Where-Object {(($UninstallPrograms -contains $_.DisplayName) -or (($_.DisplayName -like "*$HPidentifier"))-and ($_.DisplayName -notin $WhitelistedApps))}

    #$InstalledPackages = Get-AppxPackage -AllUsers | Where-Object {(($UninstallPrograms -contains $_.Name) -or (($_.Name -like "^$HPidentifier"))-and ($_.Name -notin $WhitelistedApps))}

    $InstalledPrograms = $allstring | Where-Object { $UninstallPrograms -contains $_.Name }
    foreach ($app in $UninstallPrograms)
    {
        if (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app -ErrorAction SilentlyContinue)
        {
            Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app | Remove-AppxProvisionedPackage -Online
            write-output "Removed provisioned package for $app."
        } else
        {
            write-output "Provisioned package for $app not found."
        }

        if (Get-AppxPackage -allusers -Name $app -ErrorAction SilentlyContinue)
        {
            Get-AppxPackage -allusers -Name $app | Remove-AppxPackage -AllUsers
            write-output "Removed $app."
        } else
        {
            write-output "$app not found."
        }

        if (Get-Package -scope allusers -Name $app -ErrorAction SilentlyContinue)
        {
            Get-Package -scope allusers -Name $app | Uninstall-Package -scope AllUsers
            write-output "Removed $app."
        } else
        {
            write-output "$app not found."
        }

        UninstallAppFull -appName $app
    }

    ##Belt and braces, remove via CIM too
    #foreach ($program in $UninstallPrograms) {
    #    Get-CimInstance -Classname Win32_Product | Where-Object Name -Match $program | Invoke-CimMethod -MethodName UnInstall
    #}

    #Remove HP Documentation if it exists
    if (test-path -Path "C:\Program Files\HP\Documentation\Doc_uninstall.cmd")
    {
        Start-Process -FilePath "C:\Program Files\HP\Documentation\Doc_uninstall.cmd" -Wait -passthru -NoNewWindow
    }

    ##Remove HP Connect Optimizer if setup.exe exists
    if (test-path -Path 'C:\Program Files (x86)\InstallShield Installation Information\{6468C4A5-E47E-405F-B675-A70A70983EA6}\setup.exe')
    {
        invoke-webrequest -uri "https://raw.githubusercontent.com/A1-Technologies/HP-DeBloat/main/De-Bloat/HPConnOpt.iss" -outfile "C:\Windows\Temp\HPConnOpt.iss"

        &'C:\Program Files (x86)\InstallShield Installation Information\{6468C4A5-E47E-405F-B675-A70A70983EA6}\setup.exe' @('-s', '-f1C:\Windows\Temp\HPConnOpt.iss')
    }

    ##Remove HP Data Science Stack Manager
    if (test-path -Path 'C:\Program Files\HP\Z By HP Data Science Stack Manager\Uninstall Z by HP Data Science Stack Manager.exe')
    {
        &'C:\Program Files\HP\Z By HP Data Science Stack Manager\Uninstall Z by HP Data Science Stack Manager.exe' @('/allusers', '/S')
    }

    ##Remove other crap
    if (Test-Path -Path "C:\Program Files (x86)\HP\Shared" -PathType Container)
    { Remove-Item -Path "C:\Program Files (x86)\HP\Shared" -Recurse -Force
    }
    if (Test-Path -Path "C:\Program Files (x86)\Online Services" -PathType Container)
    { Remove-Item -Path "C:\Program Files (x86)\Online Services" -Recurse -Force
    }
    if (Test-Path -Path "C:\ProgramData\HP\TCO" -PathType Container)
    { Remove-Item -Path "C:\ProgramData\HP\TCO" -Recurse -Force
    }
    if (Test-Path -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Amazon.com.lnk" -PathType Leaf)
    { Remove-Item -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Amazon.com.lnk" -Force
    }
    if (Test-Path -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Angebote.lnk" -PathType Leaf)
    { Remove-Item -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Angebote.lnk" -Force
    }
    if (Test-Path -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\TCO Certified.lnk" -PathType Leaf)
    { Remove-Item -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\TCO Certified.lnk" -Force
    }
    if (Test-Path -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Booking.com.lnk" -PathType Leaf)
    { Remove-Item -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Booking.com.lnk" -Force
    }
    if (Test-Path -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Adobe offers.lnk" -PathType Leaf)
    { Remove-Item -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Adobe offers.lnk" -Force
    }
    if (Test-Path -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Miro Offer.lnk" -PathType Leaf)
    { Remove-Item -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Miro offer.lnk" -Force
    }

    ##Remove Wolf Security
    #Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -eq 'HP Wolf Security' } | Invoke-CimMethod -MethodName Uninstall
    #Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -eq 'HP Wolf Security - Console' } | Invoke-CimMethod -MethodName Uninstall
    #Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -eq 'HP Security Update Service' } | Invoke-CimMethod -MethodName Uninstall

    # Main execution
    Write-output "Starting HP security package uninstallation process"

    # Define packages and criteria
    $packagePatterns = @(
        @{ Name = "HP Client Security Manager"; MinVersion = "10.0.0" },
        @{ Name = "HP Wolf Security(?!.*Console)" },
        @{ Name = "HP Wolf Security.*Console" },
        @{ Name = "HP Security Update Service" }
    )

    # Process each package pattern
    foreach ($pattern in $packagePatterns)
    {
        $patternName = $pattern.Name
        $minVersion = $pattern.MinVersion
        Write-Output "Checking for packages matching pattern: $patternName"

        # Search for matching packages in the registry
        $matchingPackages = @()

        # Check in 32-bit and 64-bit registry locations
        $registryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )

        foreach ($registryPath in $registryPaths)
        {
            $packages = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match [regex]::Escape($patternName) }

            # Filter by minimum version if specified
            if ($minVersion -and $packages)
            {
                $packages = $packages | Where-Object {
                    if ($_.DisplayVersion)
                    {
                        try
                        {
                            [version]$_.DisplayVersion -ge [version]$minVersion
                        } catch
                        {
                            # If version comparison fails, include it anyway for safety
                            $true
                        }
                    } else
                    {
                        # If no version information, include it for safety
                        $true
                    }
                }
            }

            $matchingPackages += $packages
        }

        if ($matchingPackages.Count -eq 0)
        {
            Write-Output "No packages found matching pattern: $patternName"
            continue
        }

        Write-Output "Found $($matchingPackages.Count) package(s) matching pattern: $patternName"

        # Process each matching package
        foreach ($package in $matchingPackages)
        {
            $displayName = $package.DisplayName
            $uninstallString = $package.UninstallString
            $quietUninstallString = $package.QuietUninstallString
            $version = $package.DisplayVersion

            Write-Output "Attempting to uninstall: $displayName (Version: $version)"

            # Try to use the UninstallAppFull function first
            Write-Output "Trying to uninstall via UninstallAppFull..."
            UninstallAppFull -appName $displayName

            ##Skip the fallback if UninstallAppFull already removed the app
            if (-not (Test-Path $package.PSPath))
            {
                Write-Output "$displayName removed by UninstallAppFull, skipping fallback"
                continue
            }

            # If UninstallAppFull doesn't work, fall back to direct uninstallation
            # Check if uninstall string exists and attempt uninstall
            if ($quietUninstallString)
            {
                Write-Output "Using quiet uninstall string: $quietUninstallString"
                try
                {
                    if ($quietUninstallString -match "msiexec")
                    {
                        # For MSI-based uninstalls, add /quiet
                        $uninstallCommand = $quietUninstallString + " /quiet"
                        Start-Process "cmd.exe" -ArgumentList "/c $uninstallCommand" -Wait -NoNewWindow
                    } else
                    {
                        # For EXE-based uninstalls
                        ##Use parseExeUninstall so quoted paths containing spaces parse correctly
                        $parsedQuiet = @(parseExeUninstall -exeString $quietUninstallString)
                        $uninstallExe = $parsedQuiet[0].Trim('"')
                        $uninstallArgs = @($parsedQuiet | Select-Object -Skip 1)

                        $quietStartParams = @{ FilePath = $uninstallExe; Wait = $true; NoNewWindow = $true }
                        if ($uninstallArgs.Count -gt 0)
                        {
                            $quietStartParams['ArgumentList'] = $uninstallArgs
                        }
                        Start-Process @quietStartParams
                    }
                    Write-Output "Quiet uninstall completed for: $displayName"
                } catch
                {
                    Write-Output "Error during quiet uninstall: $_"
                }
            } elseif ($uninstallString)
            {
                Write-Output "Using standard uninstall string: $uninstallString"
                try
                {
                    if ($uninstallString -match "msiexec")
                    {
                        # For MSI-based uninstalls, add /quiet
                        if ($uninstallString -match "/I{")
                        {
                            # Change /I to /X for uninstall if needed
                            $uninstallString = $uninstallString -replace "/I", "/X"
                        }
                        $uninstallCommand = $uninstallString + " /quiet"
                        Start-Process "cmd.exe" -ArgumentList "/c $uninstallCommand" -Wait -NoNewWindow
                    } else
                    {
                        # For EXE-based uninstalls
                        ##Use parseExeUninstall so quoted paths containing spaces parse correctly
                        $parsedStandard = @(parseExeUninstall -exeString $uninstallString)
                        $uninstallExe = $parsedStandard[0].Trim('"')
                        $uninstallArgs = @($parsedStandard | Select-Object -Skip 1)

                        # Add silent parameters for common installers
                        if ($uninstallString -match "uninstall.exe|uninst.exe|setup.exe|installer.exe")
                        {
                            $uninstallArgs += @("/S", "/silent", "/quiet", "/uninstall")
                        }

                        $standardStartParams = @{ FilePath = $uninstallExe; Wait = $true; NoNewWindow = $true }
                        if ($uninstallArgs.Count -gt 0)
                        {
                            $standardStartParams['ArgumentList'] = $uninstallArgs
                        }
                        Start-Process @standardStartParams
                    }
                    Write-Output "Standard uninstall completed for: $displayName"
                } catch
                {
                    Write-Output "Error during standard uninstall: $_"
                }
            } else
            {
                Write-Output "No uninstall string found for: $displayName"
            }
        }
    }

    ##Use Winget to catch Wolf Security
    ##    Write-Output "Attempting to uninstall HP Wolf Security via Winget"
    ##    $ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe"
    ##        if ($ResolveWingetPath){
    ##               $WingetPath = $ResolveWingetPath[-1].Path
    ##        }

    ##    $Winget = $WingetPath + "\winget.exe"
    ##    &$winget install --id "$appid" --silent --force --accept-package-agreements --accept-source-agreements --exact | out-null

    ##    write-output "Removed HP bloat"
}
