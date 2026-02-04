Write-Host "----------------------------------"
Write-Host " Script de Bienvenida - Windows  "
Write-Host "----------------------------------"

Write-Host "Nombre del equipo:"
$env:COMPUTERNAME
Write-Host ""

Write-Host "IP actual:"
Get-NetIPAddress -AddressFamily IPv4 |
 Where-Object {$_.IPAddress -notlike "169.254*"} |
 Select-Object InterfaceAlias,IPAddress,PrefixLength |
 Format-Table -AutoSize

Write-Host ""
Write-Host "Espacio en disco:"
Get-PSDrive -PSProvider FileSystem |
 Select-Object Name,Used,Free |
 Format-Table -AutoSize

Write-Host "-----------------------------------"