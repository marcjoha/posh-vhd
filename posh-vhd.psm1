<#
Name:       posh-vhd.psm1
Author:     Marcus Johansson (@marcjoha)
Created:    2013-03-15
Modified:   2013-03-19

Functions:
    Get-MountedDisks
    Mount-Disk
    Dismount-Disk
    New-DiffDisk
    Add-BootConfiguration
#>

function Get-MountedDisks() {
    # Diskpart instructions for listing virtual disks
    $script = "LIST VDISK"

    $proc = Run-Diskpart $script
    $output = $proc.StandardOutput.ReadToEnd()
    ($output | Out-String) -split "`n" |
        Select-String -Pattern "VDisk \d+" |
        ForEach-Object {
            Write-Output $_.Line.Remove(0, 57)
        }   
}
Export-ModuleMember -Function Get-MountedDisks

function Mount-Disk() {
    param (
        [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$false)]
        [ValidateScript({Test-Path $_ -PathType 'Leaf'})] 
        [string]$VhdPath
    )
    
    $VhdPath = Resolve-Path $VhdPath -ErrorAction Stop

    # Diskpart instructions for attaching a virtual disk
    $script = "SELECT VDISK FILE=`"{0}`"`r`n" -f $VhdPath 
    $script += "ATTACH VDISK"
    
    Write-Host ("Attempting to mount disk [{0}]" -f $VhdPath)
    $proc = Run-Diskpart $script
    
    if ($proc.ExitCode -eq 0) {
        Write-Host -ForegroundColor DarkGreen "Operation finished succesfully"
    } else {
        Write-Host -ForegroundColor Red "Something went wrong when running diskpart.exe. The output was: "
        Write-Host $proc.StandardOutput.ReadToEnd()
    }
}
Export-ModuleMember -Function Mount-Disk

function Dismount-Disk() {
    param (
        [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$false)]
        [ValidateScript({Test-Path $_ -PathType 'Leaf'})] 
        [string]$VhdPath
    )
    
    $VhdPath = Resolve-Path $VhdPath -ErrorAction Stop  
    
    # Diskpart instructions for attaching a virtual disk
    $script  = "SELECT VDISK FILE=`"{0}`"`r`n" -f $VhdPath  
    $script += "DETACH VDISK"   
    
    Write-Host ("Attempting to dismount disk [{0}]" -f $VhdPath)
    $proc = Run-Diskpart $script
    
    if ($proc.ExitCode -eq 0) {
        Write-Host -ForegroundColor DarkGreen "Operation finished succesfully"
    } else {
        Write-Host -ForegroundColor Red "Something went wrong when running diskpart.exe. The output was: "
        Write-Host $proc.StandardOutput.ReadToEnd()
    }
}
Export-ModuleMember -Function Dismount-Disk

function New-DiffDisk() {
    param (
        [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$false)]
        [ValidateScript({Test-Path $_ -PathType 'Leaf'})] 
        [string]$VhdPath,
        [Parameter(Position=1,Mandatory=$true,ValueFromPipeline=$false)]
        [ValidateScript({Test-Path $_ -PathType 'Container'})] 
        [string]$DiffVhdDir,        
        [Parameter(Position=2,Mandatory=$true,ValueFromPipeline=$false)]
        [ValidatePattern({^[\w_]+$})]
        [string]$DiffVhdName
    )

    $VhdPath = Resolve-Path $VhdPath -ErrorAction Stop
    $DiffVhdDir = Resolve-Path $DiffVhdDir -ErrorAction Stop
    
    # Create name of new diff disk
    $DiffVhdPath = Join-Path $DiffVhdDir ($DiffVhdName + ".vhd")
    if(Test-Path $DiffVhdPath) {
        Write-Host -ForegroundColor Red ("Proposed filename for diff disk already exists [{0}]" -f $DiffVhdPath)
        Break
    }
    
    # Diskpart instructions for creating a diff disk
    $script  = "CREATE VDISK FILE=`"{0}`" PARENT=`"{1}`"" -f $DiffVhdPath, $VhdPath
    
    Write-Host ("Attempting to create diff disk [{0}]" -f $DiffVhdPath)
    $proc = Run-Diskpart $script
    
    if ($proc.ExitCode -eq 0) {
        Write-Host -ForegroundColor DarkGreen "Operation finished succesfully"
        Write-Output -InputObject $DiffVhdPath
    } else {
        Write-Host -ForegroundColor Red "Something went wrong when running diskpart.exe. The output was: "
        Write-Host $proc.StandardOutput.ReadToEnd()
    }
    
    #
}
Export-ModuleMember -Function New-DiffDisk

function Add-BootConfiguration() {
    param (
        [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$false)]
        [ValidateScript({Test-Path $_ -PathType 'Leaf'})] 
        [string]$VhdPath,
        [Parameter(Position=1,Mandatory=$true,ValueFromPipeline=$false)]
        [ValidatePattern({^[\w_]+$})]
        [string]$Name
    )

    $VhdPath = Resolve-Path $VhdPath -ErrorAction Stop

    # Get paths expected by bcdedit
    $DrivePath = Split-Path -Path $VhdPath -Qualifier
    $UnqualifiedPath = Split-Path -Path $VhdPath -NoQualifier

    Write-Host "Attempting to modify boot menu"

    $Copy = bcdedit /copy '{current}' /d $Name
    $CLSID = $Copy | ForEach-Object {$_.Remove(0,37).Replace(".","")} 
    $output  = bcdedit /set $CLSID device vhd=[$DrivePath]""$UnqualifiedPath""
    $output += "`r`n"
    $output += bcdedit /set $CLSID osdevice vhd=[$DrivePath]""$UnqualifiedPath""
    $output += "`r`n"
    $output += bcdedit /set $CLSID detecthal on
    
    # Inspect bcdedit's output for errors
    if (($output | Select-String "The operation completed successfully" | Measure-Object -Line).Lines -eq 3) {
        Write-Host -ForegroundColor DarkGreen "Operation finished succesfully"
    } else {
        Write-Host -ForegroundColor Red "Something went wrong when running bcdedit.exe. The output was: "
        Write-Host $output
    }   
}
Export-ModuleMember -Function Add-BootConfiguration

function Run-Diskpart($script) {
    # Store the diskpart instructions in a temporary file
    $tempFile = [IO.Path]::GetTempFileName()
    $script | Set-Content $tempFile

    # Run diskpart and fetch output
    $procInfo = New-Object System.Diagnostics.ProcessStartInfo
    $procInfo.FileName = "diskpart.exe"
    $procInfo.Arguments = "/s {0}" -f $tempFile 
    $procInfo.RedirectStandardError = $true
    $procInfo.RedirectStandardOutput = $true
    $procInfo.UseShellExecute = $false
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $procInfo
    $proc.Start() | Out-Null
    $proc.WaitForExit()

    # Remove temporary file
    Remove-Item $tempFile   
    
    # Return process object for the callee to decide what to do
    return $proc
}



