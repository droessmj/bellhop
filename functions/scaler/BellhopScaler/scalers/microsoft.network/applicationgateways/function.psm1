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

    # TODO: build tier map to sku name
    # TODO: When running every minute, this scaling ends up superceding itself as it generally doesn't complete in under one minute. May need a way to check the resoruce 
    #       an in-process scaling operation and bail if in place...
    
    # need to populate the gateway model from the graph data instead of doing a lookup. Likely requires a helper function and some testing as it's not straightforward
    $config = Get-ApplicationGatewayConfig -graphData $graphData

    # name, rgname, resource type, location, properties to patch
    #$config = Get-AzApplicationGateway -Name $graphData.name -ResourceGroupName $graphData.resourceGroup

    switch ($direction) {
        'up' {
            Write-Host "Scaling Application Gateway Size: '$($graphData.name)' to Tier: '$($tagData.saveData.tier)'"

            #there's probably a more elegant way to do this, but for now we're starting with the brutish approach

            # TODO: tier and name need to match up correctly
            if ($tagData.saveData.tier){$config.sku.tier = $tagData.saveData.tier}
            if ($tagData.saveData.SkuName){$config.sku.name = $tagData.saveData.skuName}
            if ($tagData.saveData.capacity){$config.sku.capacity = $tagData.saveData.capacity}
            if ($tagData.saveData.minCapacity){$config.autoscaleConfiguration.minCapacity = $tagData.saveData.minCapacity}
            if ($tagData.saveData.maxCapacity){$config.autoscaleConfiguration.maxCapacity = $tagData.saveData.maxCapacity}
        }

        'down' {
            Write-Host "Scaling Application Gateway Size: '$($graphData.name)' to Tier: '$($tagData.setData.tier)'"

            # TODO: tier and name need to match up...
            #       also need to add business logic which prevents scaling between v1 and v2 tiers as it does not seem to be supported            
            $config.Sku.Tier = $tagData.setData.tier
            $config.Sku.Name = $tagData.setData.skuName

            $saveData = @{
                SkuName = $graphData.properties.sku.name
                Tier = $graphData.properties.sku.tier
            }

            if ( $tagData.setData.Keys -Contains "Capacity") { 
                $config.Sku.Capacity = $tagData.setData.capacity

                $saveData += @{
                    Capacity = $graphData.properties.sku.capacity
                }
            } else{
                # autoscale capacities should not be reachable if manual capacity is specified

                # autoscale is only valid with v2 SKUs 
                if($tagData.setData.tier -eq "Standard_v2" -or $tagData.setData.tier -eq "WAF_v2") {
                    # maybe in the future should add a check for max -gte to min
                    if ( $tagData.setData.minCapacity -and $tagData.setData.maxCapacity) { 
                        #TODO: min must be -lte max
                        $config.AutoscaleConfiguration.MinCapacity = $tagData.setData.minCapacity
                        $config.AutoscaleConfiguration.MaxCapacity = $tagData.setData.maxCapacity

                        $saveData += @{
                            MinCapacity = $graphData.properties.autoscaleConfiguration.minCapacity
                            MaxCapacity = $graphData.properties.autoscaleConfiguration.maxCapacity
                        }
                    }
                }
            }

            $config.Tag += Set-SaveTags $saveData
        }
    }

    # Scale the Gateway
    try {
        #given limited scope it may be easy to take this approach to patch the remote resource...
        #https://docs.microsoft.com/en-us/powershell/module/az.resources/set-azresource?view=azps-5.7.0

        #TODO: need to get this to be a PSResource
        $finalConfig = @{
            Name = $config.Name
            ResourceGroupName = $config.resourcegroup
            ResourceType = "Microsoft.Network/applicationGateways"
            Properties = @{
                Sku = $config.Sku
                AutoscaleConfiguration = $config.AutoscaleConfiguration
            }
        }

        #convert config to PsResource and pipe to set-azresource with appropriate type info
        Set-AzResource @finalConfig -UsePatchSemantics -Force
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

function Get-ApplicationGatewayConfig{
    param(
        $graphData
    )

    $newGwObj = New-Object -TypeName Microsoft.Azure.Commands.Network.Models.PSApplicationGateway
    $newGwObj.ResourceGroupName = $graphData.resourceGroup
    $newGwObj.Name = $graphData.name
    $newGwObj.Location = $graphData.location
    $newGwObj.Sku = New-Object -TypeName Microsoft.Azure.Commands.Network.Models.PSApplicationGatewaySku
    $newGwObj.Sku.Name = $graphData.properties.sku.name
    $newGwObj.Sku.Tier = $graphData.properties.sku.tier
    $newGwObj.Sku.Capacity = $graphData.properties.sku.capacity
    $newGwObj.AutoscaleConfiguration = New-Object -TypeName Microsoft.Azure.Commands.Network.Models.PSApplicationGatewayAutoscaleConfiguration
    $newGwObj.AutoscaleConfiguration.MinCapacity = $graphData.properties.autoscaleConfiguration.minCapacity
    $newGwObj.AutoscaleConfiguration.MaxCapacity = $graphData.properties.autoscaleConfiguration.maxCapacity

    return $newGwObj
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
