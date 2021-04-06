#
# AZURE VIRTUAL MACHINE SCALE FUNCTION
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

    $sizeMap = @{
        Standard_Small      = "Small"
        Standard_Medium     = "Medium"
        Standard_Large      = "Large"
        Standard_v2         = "Standard_v2"
        WAF_Medium          = "WAF_Medium"
        WAF_Large           = "WAF_Large"
        WAF_v2              = "WAF_v2"
    }

    $baseData = @{
        ResourceGroupName = $graphData.resourceGroup
        Name = $graphData.name
    }

    $config = @{ }
    $tags = $tagData.tags

    switch ($direction) {
        'up' {
            Write-Host "Scaling Application Gateway Size: '$($graphData.name)' to Tier: '$($tagData.saveData.Tier)'"

            $config = $baseData + $tagData.saveData
        }

        'down' {
            Write-Host "Scaling Application Gateway Size: '$($graphData.name)' to Tier: '$($tagData.setData.Tier)'"

            $config = @{
                Tier = $tagData.setData.Tier
            }

            $saveData = @{
                Tier = $graphData.sku.tier
            }

            if ( $tagData.setData.Capacity ) { 
                $config.Add("Capacity", $tagData.setData.Capacity) 

                $saveData += @{
                    Capacity = $graphData.sku.capacity
                }
            } else{
                # autoscale capacities should not be reachable if manual capacity is specified

                # autoscale is only valid with v2 SKUs 
                if($graphData.sku.tier -eq "Standard_v2" -or $graphData.sku.tier -eq "WAF_v2") {
                    # maybe in the future should add a check for max -gte to min
                    if ( $tagData.setData.MinCapacity ) { $config.Add("MinCapacity", $tagData.setData.MinCapacity) }
                    if ( $tagData.setData.MaxCapacity ) { $config.Add("MaxCapacity", $tagData.setData.MaxCapacity) }

                    $saveData += @{
                        MinCapacity = $graphData.autoscaleConfiguration.minCapacity
                        MaxCapacity = $graphData.autoscaleConfiguration.maxCapacity
                    }
                }
            }

            $config += $baseData
            $tags += Set-SaveTags $saveData
        }
    }

    # Scale the Gateway
    try {
        Set-AzApplicationGateway @config -Tag $tags
    }
    catch {
        Write-Host "Error scaling Application Gateway: $($graphData.name)"
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
