function get-appendedResults
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, HelpMessage="File path to grab commits for")]
        $filePath,
        [Parameter(Mandatory=$true, HelpMessage="Output File path without extension")]
        $outFile,
        $state_id="",
        [switch]$splitState,
        $maxFiles=0
    )

    $origOutFile = $outFile

    if ( $state_id.Length -gt 0 )
    {
        $outFile = $outFile + "_" + $state_id + ".csv"
        Write-Verbose "building $outFile using $filePath filtered by state $state_id"
    }
    else 
    {
        Write-Verbose "building $outFile using all data from $filePath"
    }

    git log --format=%H --reverse $filePath | out-file commits.txt

    $commits = get-content commits.txt

    # greb the last part of the file name
    $fileName = ($filePath -split "\\")[-1]
    $commitCount = $commits.Length

    $fullCount = 0

    write-verbose "there are $commitCount commits to fetch for $filePath ( $fileName )"
    
    $currentCommitIndex = 0

    if ( $maxFiles -gt 0 )
    {
        $commits = $commits[0..$($maxFiles-1)]
    }

    $allCommits = $commits.Length

    foreach( $commit in $commits )
    {
        $newJson = git show ${commit}:${filePath} | ConvertFrom-Json -Depth 20
        write-verbose "commit $commit ($currentCommitIndex of $allCommits ) was grabbed"

        $currentCommitIndex++

        $rows = @()

        foreach( $r in $newJson.data.races )
        {
            if (( $state_id.Length -eq 0) -or ($state_id -eq $r.state_id ))
            {
                $c = $r.candidates

                $sc = @{}
                $c | % { $sc.Add( $_.candidate_key, $_)}

                $csv = [ordered]@{ 
                        collection_timestamp = $newJson.meta.timestamp;
                        state_id = $r.state_id;
                        state_last_updated = $r.last_updated;
                        state_inperson_votes = $r.votes;
                        state_absentee_votes = $r.absentee_votes;
                        state_precincts_reported = $r.precincts_reporting;
                        state_precincts_avail = $r.precincts_total;
                        state_trump_inperson_votes = $sc["trumpd"].votes;
                        state_trump_absentee_votes = $sc["trumpd"].absentee_votes;
                        state_biden_inperson_votes = $sc["bidenj"].votes;
                        state_biden_absentee_votes = $sc["bidenj"].absentee_votes;
                        state_jorgensen_inperson_votes = $sc["jorgensenj"].votes;
                        state_jorgensen_absentee_votes = $sc["jorgensenj"].absentee_votes;
                        state_ventura_inperson_votes = $sc["venturaj"].votes;
                        state_ventura_absentee_votes = $sc["venturaj"].absentee_votes;                      
                        }
                
                foreach( $co in $r.counties )
                {
                    $cc = $co.results
                    $cr = $co.results_absentee

                    $csvc = [ordered]@{county_name = $co.name;
                            county_fips = $co.fips;
                            county_last_updated = $co.last_updated
                            county_inperson_votes = $co.votes;
                            county_absentee_votes = $co.absentee_votes;
                            county_total_exp_votes = $co.tot_exp_vote;
                            county_trump_inperson_votes = $cc.trumpd;
                            county_biden_inperson_votes = $cc.bidenj;
                            county_jorgensen_inperson_votes = $cc.jorgensenj;
                            county_ventura_inperson_votes = $cc.venturaj;
                            county_trump_absentee_votes = $cr.trumpd;
                            county_biden_absentee_votes = $cr.bidenj;
                            county_jorgensen_absentee_votes = $cr.jorgensenj;
                            county_ventura_absentee_votes = $cr.venturaj;
                            }

                    $full_csv = $csv + $csvc

                    $rows += new-object psobject -Property $full_csv
                }
            }
        }

        if ( $fullCount -eq 0 )
        {
            $fullCount = $rows.Count * $allCommits
        }

        $stateList = @()
        $reportFile = $outFile

        if ( $splitState )
        {
            $stateList = $newJson.data.races.state_id
            $reportFile = $origOutFile + "_*.csv ( $($stateList.Count) files )"
        }

        Write-Verbose "$($rows.Count) rows created so far ($fullCount expected)"
        Write-Progress -Activity "Grabbing all Commits of $fileName into $reportFile" -id 0 `
                        -status "Commit $commit ($currentCommitIndex of $allCommits) ($($rows.count) written, $fullCount expected)" `
                        -PercentComplete (($currentCommitIndex/$allCommits)*100)

        $stateList = @()

        #splitting by state
        if ( $stateList.Count -gt 0)
        {
            foreach( $theState in $stateList )
            {
                $outFile = $origOutFile + "_" + $theState + ".csv"
                $reportFile = $outFile + "_*.csv"
                if ( $currentCommitIndex -eq 1)
                {
                    $rows | ? { $_.state_id -eq $theState } | export-csv -UseQuotes AsNeeded $outFile
                }
                else 
                {
                    $rows | ? { $_.state_id -eq $theState } | export-csv -UseQuotes AsNeeded -append $outFile
                }
            }
        }
        else 
        {
            if ( $currentCommitIndex -eq 1)
            {
               $rows | export-csv -UseQuotes AsNeeded $outFile
            }
            else 
            {
                $rows | export-csv -UseQuotes AsNeeded -append $outFile
            }                
        }
    }
}