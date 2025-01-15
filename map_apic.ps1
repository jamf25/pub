# PowerShell script to retrieve network information from Cisco APIC

# APIC connection parameters
$apicHost = "https://your-apic-ip"
$username = "admin"

# Prompt for password securely
$securePassword = Read-Host -Prompt "Enter your APIC password" -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)

# Immediately clear the password from memory after converting
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

# Ignore SSL certificate validation (remove in production)
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# Function to get APIC authentication token
function Get-ApicToken {
    param (
        [string]$apicHost,
        [string]$username,
        [string]$password
    )
    
    $uri = "$apicHost/api/aaaLogin.json"
    $body = @{
        aaaUser = @{
            attributes = @{
                name = $username
                pwd = $password
            }
        }
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType 'application/json'
        return $response.imdata[0].aaaLogin.attributes.token
    }
    catch {
        Write-Error "Failed to authenticate: $_"
        exit 1
    }
}

# Function to get all tenants
function Get-ApicTenants {
    param (
        [string]$apicHost,
        [string]$token
    )

    $uri = "$apicHost/api/node/class/fvTenant.json"
    $headers = @{
        'Cookie' = "APIC-Cookie=$token"
    }

    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        return $response.imdata
    }
    catch {
        Write-Error "Failed to retrieve tenants: $_"
        return $null
    }
}

# Function to get VRFs for a tenant
function Get-ApicVRFs {
    param (
        [string]$apicHost,
        [string]$token,
        [string]$tenantDn
    )

    $uri = "$apicHost/api/node/mo/$tenantDn.json?query-target=children&target-subtree-class=fvCtx"
    $headers = @{
        'Cookie' = "APIC-Cookie=$token"
    }

    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        return $response.imdata
    }
    catch {
        Write-Error "Failed to retrieve VRFs: $_"
        return $null
    }
}

# Function to get bridge domains for a tenant
function Get-ApicBridgeDomains {
    param (
        [string]$apicHost,
        [string]$token,
        [string]$tenantDn
    )

    $uri = "$apicHost/api/node/mo/$tenantDn.json?query-target=children&target-subtree-class=fvBD"
    $headers = @{
        'Cookie' = "APIC-Cookie=$token"
    }

    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        return $response.imdata
    }
    catch {
        Write-Error "Failed to retrieve bridge domains: $_"
        return $null
    }
}

# Function to get application profiles and EPGs for a tenant
function Get-ApicAppProfilesAndEPGs {
    param (
        [string]$apicHost,
        [string]$token,
        [string]$tenantDn
    )

    $uri = "$apicHost/api/node/mo/$tenantDn.json?query-target=subtree&target-subtree-class=fvAp,fvAEPg"
    $headers = @{
        'Cookie' = "APIC-Cookie=$token"
    }

    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        return $response.imdata
    }
    catch {
        Write-Error "Failed to retrieve application profiles and EPGs: $_"
        return $null
    }
}

# Function to get subnets for a bridge domain
function Get-ApicSubnets {
    param (
        [string]$apicHost,
        [string]$token,
        [string]$bdDn
    )

    $uri = "$apicHost/api/node/mo/$bdDn.json?query-target=children&target-subtree-class=fvSubnet"
    $headers = @{
        'Cookie' = "APIC-Cookie=$token"
    }

    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        return $response.imdata
    }
    catch {
        Write-Error "Failed to retrieve subnets: $_"
        return $null
    }
}

# Function to get BD to VRF relation
function Get-ApicBDtoVRF {
    param (
        [string]$apicHost,
        [string]$token,
        [string]$bdDn
    )

    $uri = "$apicHost/api/node/mo/$bdDn.json?query-target=children&target-subtree-class=fvRsCtx"
    $headers = @{
        'Cookie' = "APIC-Cookie=$token"
    }

    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        if ($response.imdata.Count -gt 0) {
            return $response.imdata[0].fvRsCtx.attributes.tnFvCtxName
        }
        return "N/A"
    }
    catch {
        Write-Error "Failed to retrieve BD to VRF relation: $_"
        return "N/A"
    }
}

# Main script execution
try {
    # Get authentication token
    $token = Get-ApicToken -apicHost $apicHost -username $username -password $password
    
    # Clear password variable from memory
    $password = $null
    [System.GC]::Collect()
    
    # Create array to store results
    $networkInfo = @()
    
    # Get all tenants
    $tenants = Get-ApicTenants -apicHost $apicHost -token $token
    
    foreach ($tenant in $tenants) {
        $tenantName = $tenant.fvTenant.attributes.name
        $tenantDn = $tenant.fvTenant.attributes.dn
        
        # Get VRFs
        $vrfs = Get-ApicVRFs -apicHost $apicHost -token $token -tenantDn $tenantDn
        
        # Get bridge domains
        $bds = Get-ApicBridgeDomains -apicHost $apicHost -token $token -tenantDn $tenantDn
        
        # Get application profiles and EPGs
        $apEpgs = Get-ApicAppProfilesAndEPGs -apicHost $apicHost -token $token -tenantDn $tenantDn
        
        foreach ($bd in $bds) {
            $bdName = $bd.fvBD.attributes.name
            $bdDn = $bd.fvBD.attributes.dn
            
            # Get VRF for this BD
            $vrf = Get-ApicBDtoVRF -apicHost $apicHost -token $token -bdDn $bdDn
            
            # Get subnets
            $subnets = Get-ApicSubnets -apicHost $apicHost -token $token -bdDn $bdDn
            
            # Get associated EPGs
            $associatedEpgs = $apEpgs | Where-Object {
                $_.fvAEPg.attributes.dn -match $bdName
            } | ForEach-Object {
                $_.fvAEPg.attributes.name
            }
            
            foreach ($subnet in $subnets) {
                $networkInfo += [PSCustomObject]@{
                    Tenant = $tenantName
                    VRF = $vrf
                    BridgeDomain = $bdName
                    ApplicationProfiles = ($apEpgs | Where-Object { $_.fvAp } | ForEach-Object { $_.fvAp.attributes.name } | Select-Object -Unique) -join '; '
                    EPGs = ($associatedEpgs | Select-Object -Unique) -join '; '
                    Subnet = $subnet.fvSubnet.attributes.ip
                    Scope = $subnet.fvSubnet.attributes.scope
                }
            }
        }
    }
    
    # Export to CSV (optional)
    $networkInfo | Export-Csv -Path "aci_network_info.csv" -NoTypeInformation
    
    # Display results in console
    $networkInfo | Format-Table -AutoSize
}
catch {
    Write-Error "Script execution failed: $_"
}
finally {
    # Clear any remaining sensitive data from memory
    if ($token) { $token = $null }
    if ($securePassword) { $securePassword.Dispose() }
    [System.GC]::Collect()
}
