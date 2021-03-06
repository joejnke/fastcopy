###
#
# This script runs robocopy jobs in parallel by increasing the number of outstanding i/o's to the copy process. Even though you can
# change the number of threads using the "/mt:#" parameter, your backups will run faster by adding two or more jobs to your
# original set. 
#
# To do this, you need to subdivide the work into directories. That is, each job will recurse the directory until completed.
# The ideal case is to have 100's of directories as the root of the backup. Simply change $src to get
# the list of folders to backup and the list is used to feed $FastCopy.
# 
# For maximum SMB throughput, do not exceed 8 concurrent Robocopy jobs with 20 threads. Any more will degrade
# the performance by causing disk thrashing looking up directory entries. Lower the number of threads to 8 if one
# or more of your volumes are encrypted.
#
# Parameters:
# $src Change this to a directory which has lots of subdirectories that can be processed in parallel 
# $dest Change this to where you want to backup your files to
# $max_jobs Change this to the number of parallel jobs to run ( <= 8 )
# $log Change this to the directory where you want to store the output of each robocopy job.
#
####
#
# This script will throttle the number of concurrent jobs based on $max_jobs
#

Function fscp {
	[CmdletBinding()]

	Param(
		[Parameter (Mandatory=$true, HelpMessage="Path to source directory to copy from")]
		[String]$srcIn,

		[Parameter (Mandatory=$true, HelpMessage="Path to destination directory to copy to")]
		[String]$destIn
	)

	Begin {
		#source directory
		$src = $srcIn + "\"

		#destination directory
		$dest = $destIn + "\"

		#logging directory and log file
		$log = $dest + "\fastcopy_log"
		mkdir $log
		$log += "\$(get-date -f yyyy-MM-dd-mm-ss).log"
	}

	Process {
		#the function that uses robocopy 
		$FastCopy = {
			param($name, $src, $dest, $log)
			robocopy $src$name $dest$name /E /nfl /np /mt:16 /ndl /LOG+:$log | Out-null
		}

		#print source and destination directories
		Write-Host "Source dir: " $src
		Write-Host "Destination dir: " $dest

		$max_jobs = 8
		$tstart = get-date

		#list directories in source dir
		$files = ls $src

		#for each directory in source dir apply threaded robocopy command.
		$files | %{
			#check the number of jobs running and Start-Sleep untill the number gets below the max_jobs
			$j = Get-Job -State "Running"
			while ($j.count -ge $max_jobs) 
			{
				 Start-Sleep -Milliseconds 500
				 $j = Get-Job -State "Running"
			}

			Get-job -State "Completed" | Receive-job	#delete job result of those completed
			Remove-job -State "Completed"	#terminate or delete completed jobs

			if ($name -eq "FL"){
				ls $name | %{Start-Job -Name $_ $FastCopy -ArgumentList $_,$src,$dest,$log | Out-null}
			}
			else {
				Start-Job -Name $_ $FastCopy -ArgumentList $_,$src,$dest,$log | Out-null
			}
		    Write-Host -NoNewline "." #to show progress
		}

	}

	End {
		Write-Host "`nwaiting for all jobs to complete ..."
		Write-host "# of Remaining jobs: "

		$rjobs = Get-Job -State "Running" 
		$jobcount = $rjobs.count
		While (Get-Job -State "Running") {
			$rjobs = Get-Job -State "Running"
			if ($rjobs.count -lt $jobcount) {
				$jobcount = $rjobs.count
				Write-host $rjobs.Name.count
			}
			Start-Sleep 2 
		}

		Remove-Job -State "Completed" 
		Write-Host "`ncopy completed ..."

		$tend = get-date

		$tspan = new-timespan -start $tstart -end $tend
		$tspanHour = ($tspan.TotalSeconds/3600 - ($tspan.TotalSeconds%3600)/3600)
		$tspanMin = ($tspan.TotalSeconds%3600/60 - ( $tspan.TotalSeconds%3600%60)/60)
		$tspanSec = ($tspan.TotalSeconds%3600%60)

		Write-host "`nTotal time to copy " $tspanHour":"$tspanMin":"$tspanSec
	}
}
