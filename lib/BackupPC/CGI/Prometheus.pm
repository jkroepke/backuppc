#=============================================================
#
# BackupPC::CGI::Prometheus package
#
# DESCRIPTION
#
#   This module implements an Prometheus page for the CGI interface.
#
# AUTHOR
#   Jan-Otto Kröpke (mail at jkroepke dot de)
#
# COPYRIGHT
#   Copyright (C) 2005-2013  Rich Duzenbury and Craig Barratt
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#========================================================================
#
# Version 4.0.0alpha3, released 1 Dec 2013.
#
# See http://backuppc.sourceforge.net.
#
#========================================================================

package BackupPC::CGI::Prometheus;

use strict;
use BackupPC::CGI::Lib qw(:all);
use Net::Prometheus;

# backuppc_info{pid=,version,started}
# backuppc_queue_count{host,user,queue=user,background,command}
# backuppc_pool_bytes
# backuppc_pool_directories
# backuppc_pool_files
# backuppc_host_state_{hostname,user,state}
# backuppc_host_backup_{hostname,number,user,type,filled,level,compression_level}
# backuppc_host_backup_bytes
# backuppc_host_backup_duration
# backuppc_host_backup_xfer_errors
# backuppc_host_backup_bad_files
# backuppc_host_backup_bad_share
# backuppc_host_backup_tar_errors
# backuppc_host_backup_total_files
# backuppc_host_backup_total_size_bytes
# backuppc_host_backup_total_throughput
# backuppc_host_backup_existing_files
# backuppc_host_backup_existing_size_bytes
# backuppc_host_backup_existing_size_compressed_bytes
# backuppc_host_backup_existing_throughput
# backuppc_host_backup_new_files
# backuppc_host_backup_new_size_bytes
# backuppc_host_backup_new_size_compressed_bytes
# backuppc_host_backup_new_throughput

sub action
{
    my($fullTot, $fullSizeTot, $incrTot, $incrSizeTot,
        $hostCntGood, $hostCntNone, $client,
        $backuppc_host_backup_bytes, $backuppc_host_backup_duration,
    );

    $client = new Net::Prometheus();

    $backuppc_host_backup_bytes = $client->new_gauge(
        name => "backuppc_host_backup_bytes",
    );

    $backuppc_host_backup_duration = $client->new_gauge(
        name => "backuppc_host_backup_duration",
    );

    $hostCntGood = $hostCntNone = 0;
    GetStatusInfo("hosts info");


    foreach my $host ( GetUserHosts(1) ) {
        my($fullDur, $incrCnt, $incrAge, $fullSize, $fullRate, $reasonHilite,
            $lastAge, $tempState, $tempReason, $lastXferErrors);
        my($shortErr);
        my @Backups = $bpc->BackupInfoRead($host);
        my $fullCnt = $incrCnt = 0;
        my $fullAge = $incrAge = $lastAge = -1;

        $bpc->ConfigRead($host);
        %Conf = $bpc->Conf();

        for ( my $i = 0 ; $i < @Backups ; $i++ ) {
            if ( $Backups[$i]{type} eq "full" ) {
                $fullCnt++;
                if ( $fullAge < 0 || $Backups[$i]{startTime} > $fullAge ) {
                    $fullAge  = $Backups[$i]{startTime};
                    $fullSize = $Backups[$i]{size};
                    $fullDur  = $Backups[$i]{endTime} - $Backups[$i]{startTime};
                }

                ->set( [ @label_values ], $value );

                $fullSizeTot += $Backups[$i]{size};
            } else {
                $incrCnt++;
                if ( $incrAge < 0 || $Backups[$i]{startTime} > $incrAge ) {
                    $incrAge = $Backups[$i]{startTime};
                }
                $incrSizeTot += $Backups[$i]{size};
            }
        }
        if ( $fullAge > $incrAge && $fullAge >= 0 )  {
            $lastAge = $fullAge;
        } else {
            $lastAge = $incrAge;
        }
        if ( $lastAge < 0 ) {
            $lastAge = "";
        } else {
            $lastAge = sprintf("%.1f", (time - $lastAge) / (24 * 3600));
        }
        if ( $fullAge < 0 ) {
            $fullAge = "";
            $fullRate = "";
        } else {
            $fullAge = sprintf("%.1f", (time - $fullAge) / (24 * 3600));
            $fullRate = sprintf("%.2f",
                $fullSize / ($fullDur <= 0 ? 1 : $fullDur));
        }
        if ( $incrAge < 0 ) {
            $incrAge = "";
        } else {
            $incrAge = sprintf("%.1f", (time - $incrAge) / (24 * 3600));
        }
        $fullTot += $fullCnt;
        $incrTot += $incrCnt;
        $fullSize = sprintf("%.2f", $fullSize / 1024);
        $incrAge = "&nbsp;" if ( $incrAge eq "" );
        $lastXferErrors = $Backups[@Backups-1]{xferErrs} if ( @Backups );
        $reasonHilite = $Conf{CgiStatusHilightColor}{$Status{$host}{reason}}
            || $Conf{CgiStatusHilightColor}{$Status{$host}{state}};
        if ( $Conf{BackupsDisable} == 1 ) {
            if ( $Status{$host}{state} ne "Status_backup_in_progress"
                && $Status{$host}{state} ne "Status_restore_in_progress" ) {
                $reasonHilite = $Conf{CgiStatusHilightColor}{Disabled_OnlyManualBackups};
                $tempState = "Disabled_OnlyManualBackups";
                $tempReason = "";
            } else {
                $tempState = $Status{$host}{state};
                $tempReason = $Status{$host}{reason};
            }
        } elsif ($Conf{BackupsDisable} == 2 ) {
            $reasonHilite = $Conf{CgiStatusHilightColor}{Disabled_AllBackupsDisabled};
            $tempState = "Disabled_AllBackupsDisabled";
            $tempReason = "";
        } else {
            $tempState = $Status{$host}{state};
            $tempReason = $Status{$host}{reason};
        }
        $reasonHilite = " bgcolor=\"$reasonHilite\"" if ( $reasonHilite ne "" );
        if ( $tempState ne "Status_backup_in_progress"
            && $tempState ne "Status_restore_in_progress"
            && $Conf{BackupsDisable} == 0
            && $Status{$host}{error} ne "" ) {
            ($shortErr = $Status{$host}{error}) =~ s/(.{48}).*/$1.../;
            $shortErr = " ($shortErr)";
        }


    }
    $fullSizeTot = sprintf("%.2f", $fullSizeTot / 1024);
    $incrSizeTot = sprintf("%.2f", $incrSizeTot / 1024);
    my $now      = timeStamp2(time);
    my $DUlastTime   = timeStamp2($Info{DUlastValueTime});
    my $DUmaxTime    = timeStamp2($Info{DUDailyMaxTime});



    print 'Content-type: text/plan', "\r\n\r\n",
    print $client->render;
}

1;
