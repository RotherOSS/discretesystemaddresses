# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2019-2022 Rother OSS GmbH, https://otobo.de/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

use Kernel::System::Ticket;    ## no critic (Modules::RequireExplicitPackage)

package Kernel::System::Ticket;    ## no critic (Modules::RequireFilenameMatchesPackage)

use strict;
use warnings;

our @ObjectDependencies = (
);

# disable redefine warnings in this scope
{
    no warnings 'redefine';    ## no critic qw(TestingAndDebugging::ProhibitNoWarnings)

    # backup original routines
    my $TicketSubjectClean = \&Kernel::System::Ticket::TicketSubjectClean;

    # Remove interdivisional ticket numbers
    *Kernel::System::Ticket::TicketSubjectClean = sub {
        my ( $Self, %Param ) = @_;

        # standard cleaned subject
        my $Subject = &{$TicketSubjectClean}(@_);

        return if !defined $Subject;

        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

        # get config options
        my $TicketHook        = $ConfigObject->Get('Ticket::Hook');
        my $TicketHookDivider = $ConfigObject->Get('Ticket::HookDivider');

        return $Subject if $Subject !~ /$TicketHook/;
        return $Subject if $ConfigObject->Get('Ticket::SubjectCleanAllNumbers');

        my $TicketID = $Self->TicketIDLookup(
            TicketNumber => $Param{TicketNumber},
            UserID       => 1,
        );

        # get linked tickets
        my %LinkedTickets = $Kernel::OM->Get('Kernel::System::LinkObject')->LinkKeyListWithData(
            Object1 => 'Ticket',
            Key1    => $TicketID,
            Object2 => 'Ticket',
            State   => 'Valid',
            Type    => 'Interdivisional',
            UserID  => 1,
        );

        return $Subject if !%LinkedTickets;

        for my $Ticket ( values %LinkedTickets ) {
            # remove all possible ticket hook formats with []
            $Subject =~ s/\[\s*\Q$TicketHook: $Ticket->{TicketNumber}\E\s*\]\s*//g;
            $Subject =~ s/\[\s*\Q$TicketHook:$Ticket->{TicketNumber}\E\s*\]\s*//g;
            $Subject =~ s/\[\s*\Q$TicketHook$TicketHookDivider$Ticket->{TicketNumber}\E\s*\]\s*//g;

            # remove all possible ticket hook formats without []
            $Subject =~ s/\Q$TicketHook: $Ticket->{TicketNumber}\E\s*//g;
            $Subject =~ s/\Q$TicketHook:$Ticket->{TicketNumber}\E\s*//g;
            $Subject =~ s/\Q$TicketHook$TicketHookDivider$Ticket->{TicketNumber}\E\s*//g;
        }

        # trim white space at the beginning or end
        $Subject =~ s/(^\s+|\s+$)//;

        return $Subject;
    };
}

1;
