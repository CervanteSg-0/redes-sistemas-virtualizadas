Write-Host "----------------------------------------"
Write-Host " Script de bienvenida - Windows"
Write-Host "----------------------------------------"
Write-Host ""

# Nombre del equipo
Write-Host "Nombre del equipo:"
Write-Host $env:COMPUTERNAME
Write-Host ""

# IP actual
Write-Host "IP actual:"
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike "169.254*" -and $_.InterfaceAlias -notlike "*Loopback*" } |
    Select-Object InterfaceAlias, IPAddress, PrefixLength |
    Format-Table -AutoSize
Write-Host ""

# Espacio en disco
Write-Host "Espacio en disco:"
Get-PSDrive -PSProvider FileSystem |
    Select-Object Name,
        @{Name="Used (GB)"; Expression={[math]::Round($_.Used / 1GB, 2)}},
        @{Name="Free (GB)"; Expression={[math]::Round($_.Free / 1GB, 2)}},
        @{Name="Total (GB)"; Expression={[math]::Round(($_.Used + $_.Free) / 1GB, 2)}} |
    Format-Table -AutoSize

Write-Host ""
Write-Host "----------------------------------------"
