param(               
        #SQL Server Name.
        [parameter(Mandatory=$true, 
               HelpMessage="Specify the Azure SQL Server name",Position=1)]
        [String] 
        [ValidateNotNullOrEmpty()] 
        $SQLServerName = $(throw "Azure SQL Server Name is required.")
    )

############################################################
# Function to execute SQL commands.
############################################################
Function InvokeSqlCommand
{
    Param([Parameter(Position=0)]
          [string] $SQLCommand,
          [Parameter(Position=1)]
          [int] $Scriptlag,
          [Parameter(Position=2)]
          [string] $Object
         )
try
	{
		$errormessage = ''

        # Execute the SQL command on ADW.
		Invoke-Sqlcmd -ServerInstance $SQLServerName -Database "ADW" -Username "adwadmin" -Password "Microsoft~1" -Query $SQLCommand -ErrorVariable errormessage -ErrorAction Stop -QueryTimeout 8000

        # If there is an error write the error.
		If($errormessage)
		{
			Write-Host $errormessage -ForegroundColor Red
		}
		Else
		{
			if($Scriptlag -eq 1)
			{
				Write-Host "Dropped view/sp $Object if exists"
			}
			else
			{                            
				Write-Host "Execution successful $Object"
			}
		}
	} 
	catch 
	{ 
		Write-Host $Error[0] -ForegroundColor Red
		Write-Host "... Execution Failed for  $object" -ForegroundColor Red
		Throw $Error[0]
		Exit 1
	}
}

$DWScriptDir = "d:\a\r1\a\_ADW-CICD-CI\drop\Contoso\"

# The sub-directories should be provided in order to deploy the SQL DW scripts.
$Subdirectories = @("Tables","Views","Functions","Stored Procedures")

for ($Count=0; $Count -lt $Subdirectories.Length; $Count++)
{        
        Write-Host "..................Create objects from "  $Subdirectories[$Count]  " Started..........................."

        # Get the scripts.
        Get-ChildItem -Path $DWScriptDir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object{

                    
        $subdir = $_.FullName + "\" + $Subdirectories[$Count];
        $SchemaName = $_.Name


        # Excluding Dependant Views which are in DependantViews.txt file 
        if($Subdirectories[$Count] -eq 'Views')
        {
            $SQLDWFiles = Get-ChildItem -Path $subdir -Filter *.sql -Recurse | where-Object {$_.directory.parent.name + '.'  +[System.IO.Path]::GetFileNameWithoutExtension($_.name) -NotIn $DependantViewsListPath} | Sort-Object name | select -expand Fullname
        }
        Else
        {
            $SQLDWFiles = Get-ChildItem $subdir  -Recurse -File -Filter "*.sql" | Sort-Object name | SELECT -expand fullname
        }

        # Deploying many files so iterate through the files
        foreach($Scriptile in $SQLDWFiles) 
        {
            $Scriptilename = [System.IO.Path]::GetFileNameWithoutExtension($Scriptile)

            $objectName = $SchemaName + "." + $Scriptilename

            #Create table only if it does not exist
            If($Subdirectories[$Count] -eq 'Tables')
            {
                #check if table exists
                $query="if  OBJECT_ID (N'$objectName', N'U') is not Null select 1 as Flag"

                $out = Invoke-Sqlcmd -ServerInstance $SQLServerName -Database "ADW" -Username "adwadmin" -Password "Microsoft~1" -Query $query -ErrorVariable errormessage -ErrorAction SilentlyContinue | Select Flag
                                
                if($errormessage)
                {
                    Write-host Error : $errormessage
                }
                If($out.Flag -eq 1)
                {
                    Write-host "$objectName Table already Exists in Database"
                                    
                }
                # Create table if not exists
                Else
                {
                                
                    Write-host "Creating table $objectName..."
                    $SQLCommandText = [Io.File]::ReadAllText($Scriptile)
                    InvokeSqlCommand $SQLCommandText 0 $ObjectName
                }
            }

            # Drop and Create View/Sp if exists
            Else
            {
                # Drop statement for views
                If($Subdirectories[$Count] -eq 'Views')
                {
                    $DropStatement="If OBject_id(N'$objectName',N'V') is Not NULL Drop View $objectName"
                }
                # Drop statement for Sp
                ElseIf ($Subdirectories[$Count] -eq 'Functions')
				{
					$DropStatement="IF OBJECT_ID(N'$objectName', N'FN') IS NOT NULL DROP FUNCTION $ObjectName"
				}
				Else
                {
                    $DropStatement="If OBject_id(N'$objectName',N'P') is Not NULL Drop Proc $objectName"
                }
                #Drop View/SP if exists
                Write-Host "Drop view/Sp if exists $objectName" 
                InvokeSqlCommand $DropStatement 1 $objectName   
                #Create View/SP
                Write-Host 'Executing file... ', $Scriptile
                $SQLCommandText = [Io.File]::ReadAllText($Scriptile)
                InvokeSqlCommand $SQLCommandText 0 $objectName
            }
		}
	}
}

Write-Host "---------------------------------------------" 
Write-Host "Deployment Complete."
Write-Host "---------------------------------------------"
exit 0