#
# AZURE APPLICATION GATEWAY SCALE FUNCTION
#

function Update-Resource {
    param (
        [Parameter(Mandatory = $true)]
        [Object]
        $graphData,

        [Parameter(Mandatory = $true)]
        [Hashtable]
        $tagData,

        [Parameter(Mandatory = $true)]
        [String]
        $direction
    )

    # Import required supporting modules
    Import-Module Az.Network

    # Set preference variables
    $ErrorActionPreference = "Stop"

    $config = Get-AzApplicationGateway -Name $graphData.Name -ResourceGroupName $graphData.resourceGroup

    switch ($direction) {
        'up' {
            Write-Host "Scaling Application Gateway Size: '$($graphData.name)' to Tier: '$($tagData.saveData.tier)'"

            #there's probably a more elegant way to do this, but for now we're starting with the brutish approach
            if ($tagData.saveData.tier){$config.sku.tier = $tagData.saveData.tier}
            if ($tagData.saveData.capacity){$config.sku.capacity = $tagData.saveData.capacity}
            if ($tagData.saveData.minCapacity){$config.autoscaleConfiguration.minCapacity = $tagData.saveData.minCapacity}
            if ($tagData.saveData.maxCapacity){$config.autoscaleConfiguration.maxCapacity = $tagData.saveData.maxCapacity}
        }

        'down' {
            Write-Host "Scaling Application Gateway Size: '$($graphData.name)' to Tier: '$($tagData.setData.tier)'"

            $config.Sku.Tier = $tagData.setData.tier

            $saveData = @{
                Tier = $graphData.sku.tier
            }

            if ( $tagData.setData.Keys -Contains "Capacity") { 
                $config.Sku.Capacity = $tagData.setData.capacity

                $saveData += @{
                    Capacity = $graphData.sku.capacity
                }
            } else{
                # autoscale capacities should not be reachable if manual capacity is specified

                # autoscale is only valid with v2 SKUs 
                if($tagData.setData.tier -eq "Standard_v2" -or $tagData.setData.tier -eq "WAF_v2") {
                    # maybe in the future should add a check for max -gte to min
                    if ( $tagData.setData.minCapacity -and $tagData.setData.maxCapacity) { 
                        $config.AutoscaleConfiguration.MinCapacity = $tagData.setData.minCapacity
                        $config.AutoscaleConfiguration.MaxCapacity = $tagData.setData.maxCapacity

                        $saveData += @{
                            MinCapacity = $graphData.autoscaleConfiguration.minCapacity
                            MaxCapacity = $graphData.autoscaleConfiguration.maxCapacity
                        }
                    }
                }
            }

            $config.Tag += Set-SaveTags $saveData
        }
    }

    # Scale the Gateway
    try {
        Set-AzApplicationGateway -ApplicationGateway $config
    }
    catch {
        Write-Host "Error scaling Application Gateway: $($graphData.name)"
        write-Host $_
        Write-Host "($($Error.exception.GetType().fullname)) - $($PSItem.ToString())"
        # throw $PSItem
        Exit
    }
    
    Write-Host "Scaler function has completed successfully!"
}

function Set-SaveTags {
    param (
        $inTags
    )

    $outTags = @{ }
    $inTags.keys | ForEach-Object { $outTags += @{("saveState-" + $_) = $inTags[$_] } }
    
    return $outTags
}

Export-ModuleMember -Function Update-Resource