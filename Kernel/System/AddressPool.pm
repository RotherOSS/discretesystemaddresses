# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2023 Rother OSS GmbH, https://otobo.de/
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

package Kernel::System::AddressPool;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(IsHashRefWithData IsArrayRefWithData);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::Queue',
    'Kernel::System::Ticket',
    'Kernel::System::LinkObject',
);

=head1 NAME

Kernel::System::AddressPool - all address pool functions

=head1 DESCRIPTION

Global module to find addresses in pools.

=head1 PUBLIC INTERFACE

=head2 new()

create an object

    my $AddressPoolObject = $Kernel::OM->Get('Kernel::System::AddressPool');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 NameList()

Get Addresses of every pools

    my %NameList = $AddressPoolObject->NameList();

    my %NameList = $AddressPoolObject->NameList(
        QueueDefault => 1,
    );

Return:

    %NameList = (
              'test1@example.com' => 'Pool1',
              'test2@example.com' => 'Pool2',
              'test3@example.com' => 'Pool3',
              ...
            )

    %NameList = (
                'Pool1' => {
                    QueueDefault => 'Junk',
                    Emails       => ['test1@example.com' ...],
                },
                'Pool2' => {
                    QueueDefault => 'Misc',
                    Emails       => ['test2@example.com' ...],
                },
                'Pool3' => {
                    QueueDefault => 'Raw',
                    Emails       => ['test3@example.com' ...],
                },
                ...
            )

=cut

sub NameList {
    my ( $Self, %Param ) = @_;

    # get object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $ConfigItems = $ConfigObject->Get('PostMaster::AddressPool') || {};
    if ( !IsHashRefWithData($ConfigItems) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "PostMaster::AddressPool is not a hash ref!",
        );
        return;
    }

    my %NameList;
    if ( $Param{QueueDefault} ) {

        for my $ConfigItem ( keys $ConfigItems->%* ) {

            my %ConfigItemData = %{ $ConfigItems->{$ConfigItem} };
            my $PoolName = $ConfigItemData{Name};
            delete($ConfigItemData{Name});
            $NameList{ $PoolName } = \%ConfigItemData;
        }
    }
    else {

        for my $ConfigItem ( keys $ConfigItems->%* ) {

            my %ConfigItemData = %{ $ConfigItems->{$ConfigItem} };
            for my $Address ( $ConfigItemData{Emails}->@* ) {
                $NameList{ $Address } = $ConfigItemData{Name};
            }
        }
    }

    return %NameList;
}

=head2 NameLookup()

Get address pool name of ticket

    my $PoolName = $AddressPoolObject->NameLookup(
        TicketID => 4,
    );

Return:

    $PoolName = "Pool1"

=cut

sub NameLookup {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{TicketID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need TicketID!",
        );
        return;
    }

    # get objects
    my $QueueObject  = $Kernel::OM->Get('Kernel::System::Queue');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # get address pool name list
    my %NameList = $Self->NameList();

    # get ticket queue id
    my $QueueID = $TicketObject->TicketQueueID(
        TicketID => $Param{TicketID},
    );

    # set ticket pool name
    my %QueueData = $QueueObject->QueueGet(
        ID => $QueueID,
    );

    my $PoolName;
    if ( $QueueData{Email} ) {
        $PoolName = $NameList{ $QueueData{Email} };
    }

    return $PoolName;
}

=head2 QueueCheck()

Check if queue exists in address pool

    my $QueueExist = $AddressPoolObject->QueueCheck(
        Queue       => 'Junk',
        AddressPool => 'Pool1',
    );

Return:

    $QueueExist = 1

    Or

    $QueueExist = 0

=cut

sub QueueCheck {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(Queue AddressPool)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # get object
    my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');

    # get address pool name list
    my %NameList = $Self->NameList();

    # get queue address pool
    my %QueueData = $QueueObject->QueueGet(
        Name => $Param{Queue},
    );

    my $QueuePool;
    if ( $QueueData{Email} ) {
        $QueuePool = $NameList{ $QueueData{Email} };
    }

    # check is queue in given address pool
    if ( !$QueuePool || $QueuePool ne $Param{AddressPool} ) {
        return;
    }

    return 1;
}

=head2 FindLinkedTicket()

Find linked ticket with 'Interdivisional' type in address pool

    my ( $LTTicketNumber, $LTTicketID ) = $AddressPoolObject->FindLinkedTicket(
        TicketID    => 4,
        AddressPool => 'Pool1',
        UserID      => 1,
    );

Return:

    ( $LTTicketNumber, $LTTicketID ) = ("2023012338000074", 5)

=cut

sub FindLinkedTicket {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(TicketID AddressPool UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # get object
    my $LinkObject = $Kernel::OM->Get('Kernel::System::LinkObject');

    # get linked tickets
    my %LinkedTickets = $LinkObject->LinkKeyListWithData(
        Object1   => 'Ticket',
        Key1      => $Param{TicketID},
        Object2   => 'Ticket',
        State     => 'Valid',
        Type      => 'Interdivisional',
        UserID    => $Param{UserID},
    );

    for my $LinkedTicket ( keys %LinkedTickets ) {

        # get ticket number / ticket id
        my $LTTicketID     = $LinkedTickets{$LinkedTicket}{TicketID};
        my $LTTicketNumber = $LinkedTickets{$LinkedTicket}{TicketNumber};

        my $LTPoolName = $Self->NameLookup(
            TicketID => $LTTicketID,
        );
        if (
            $LTPoolName
            &&
            ( $LTPoolName eq $Param{AddressPool} )
        ) {

            return ( $LTTicketNumber, $LTTicketID );
        }
    }

    return;
}

=head2 InterdivisionalTicketLinkAdd()

Add link for address pool tickets with new 'Interdivisional' type

    $AddressPoolObject->InterdivisionalTicketLinkAdd(
        TicketIDs => [1, 5, 8],
        UserID    => 1,
    );

=cut

sub InterdivisionalTicketLinkAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(TicketIDs UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    if ( !IsArrayRefWithData($Param{TicketIDs}) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need TicketIDs as array ref!",
        );
        return;
    }

    my @TicketIDs = $Param{TicketIDs}->@*;
    if ( scalar(@TicketIDs) < 2 ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need at least 2 ticket ids!",
        );
        return;
    }

    # get object
    my $LinkObject = $Kernel::OM->Get('Kernel::System::LinkObject');

    # link tickets
    for my $SourceTicketID ( @TicketIDs ) {
        for my $TargetTicketID ( @TicketIDs ) {

            if ( $SourceTicketID == $TargetTicketID ) {
                next;
            }

            my $Success = $LinkObject->LinkAdd(
                SourceObject => 'Ticket',
                SourceKey    => $SourceTicketID,
                TargetObject => 'Ticket',
                TargetKey    => $TargetTicketID,
                Type         => 'Interdivisional',
                State        => 'Valid',
                UserID       => $Param{UserID},
            );
            if ( !$Success ) {

                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority      => 'error',
                    Message         => "Can't create a interdivisional link from ticket (ID: $SourceTicketID) to ticket (ID: $TargetTicketID)",
                );
            }
        }
    }

    return 1;
}

1;
