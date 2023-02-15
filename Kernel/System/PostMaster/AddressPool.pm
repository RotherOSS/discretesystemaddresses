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

package Kernel::System::PostMaster::AddressPool;

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

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get parser object
    $Self->{ParserObject} = $Param{ParserObject} || '';

    # Get communication log object.
    $Self->{CommunicationLogObject} = $Param{CommunicationLogObject} || '';

    return $Self;
}

=head2 FilterPools()

Return pools addressed in the address list of To, Cc ...

    my @AddressedPools = $AddressPoolObject->FilterPools(
        Params => $GetParam,
    );

=cut

sub FilterPools {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Self->{ParserObject} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need ParserObject!",
        );
        return;
    }

    if ( !IsHashRefWithData( $Param{Params} ) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need Params as hash ref!",
        );
        return;
    }

    # get headers
    my %GetParam = $Param{Params}->%*;

    # check possible address headers
    my %PoolsSeen;
    my @Pools;
    HEADER:
    for my $Header (qw(Resent-To Envelope-To To Cc Delivered-To X-Original-To)) {

        next HEADER if !$GetParam{$Header};

        my @Emails = $Self->{ParserObject}->SplitAddressLine( Line => $GetParam{$Header} );
        EMAIL:
        for my $Email (@Emails) {

            next EMAIL if !$Email;

            my $Address = $Self->{ParserObject}->GetEmailAddress( Email => $Email );

            next EMAIL if !$Address;

            my $AddressPool = $Self->PoolLookup(
                Address => $Address
            );

            next EMAIL if !$AddressPool;

            next EMAIL if $PoolsSeen{ $AddressPool }++;

            push @Pools, $AddressPool;
        }
    }

    return @Pools;
}

=head2 AddressList()

Get all addresses defined in addresspools

    my %AddressToPool = $AddressPoolObject->AddressList();

Return:

    %AddressToPool = (
              'test1@example.com' => 'Pool1',
              'test2@example.com' => 'Pool2',
              'test3@example.com' => 'Pool3',
              ...
            )

=cut

sub AddressList {
    my ( $Self, %Param ) = @_;

    return $Self->{AddressToPool}->%* if $Self->{AddressToPool};

    $Self->{AddressToPool} = {};
    my $PoolConfigs        = $Kernel::OM->Get('Kernel::Config')->Get('PostMaster::AddressPool');

    if ( !$PoolConfigs ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'debug',
            Message  => "No pools defined in PostMaster::AddressPool.",
        );

        return ();
    }

    POOL:
    for my $Pool ( keys $PoolConfigs->%* ) {
        next POOL if !$PoolConfigs->{ $Pool }{Emails};

        for my $Address ( $PoolConfigs->{ $Pool }{Emails}->@* ) {
            $Self->{AddressToPool}{ $Address } = $Pool;
        }
    }

    return $Self->{AddressToPool}->%*;
}

=head2 PoolLookup()

Get address pool by address or ticket id

    my $PoolName = $AddressPoolObject->NameLookup(
        Address  => 'test1@example.com',
    );

    my $PoolName = $AddressPoolObject->NameLookup(
        TicketID => 4,
    );

Return:

    $PoolName = "Pool1"

=cut

sub PoolLookup {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Address} && !$Param{TicketID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need Address or TicketID!",
        );
        return;
    }

    # get address pool name list
    my %AddressToPool = $Self->AddressList();

    return $AddressToPool{ $Param{Address} } if $Param{Address};

    # get objects
    my $QueueObject  = $Kernel::OM->Get('Kernel::System::Queue');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # get ticket queue id
    my $QueueID = $TicketObject->TicketQueueID(
        TicketID => $Param{TicketID},
    );

    # set address pool name
    my %QueueData = $QueueObject->QueueGet(
        ID => $QueueID,
    );

    return if !$QueueData{Email};

    return $AddressToPool{ $QueueData{Email} };
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

    # get queue
    my %Queue = $Kernel::OM->Get('Kernel::System::Queue')->QueueGet(
        Name => $Param{Queue},
    );

    return if !%Queue;

    my $Pool = $Self->PoolLookup(
        Address => $Queue{Email},
    );

    return if !$Pool;
    return if $Pool ne $Param{AddressPool};

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
        Object1 => 'Ticket',
        Key1    => $Param{TicketID},
        Object2 => 'Ticket',
        State   => 'Valid',
        Type    => 'Interdivisional',
        UserID  => $Param{UserID},
    );

    for my $LinkedTicket ( keys %LinkedTickets ) {

        # get ticket number / ticket id
        my $LTTicketID     = $LinkedTickets{$LinkedTicket}{TicketID};
        my $LTTicketNumber = $LinkedTickets{$LinkedTicket}{TicketNumber};

        my $LTPool = $Self->PoolLookup(
            TicketID => $LTTicketID,
        );

        if ( $LTPool && $LTPool eq $Param{AddressPool} ) {
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

    if ( !IsArrayRefWithData( $Param{TicketIDs} ) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need TicketIDs as array ref!",
        );
        return;
    }

    my @TicketIDs;
    my %Seen;
    ID:
    for my $ID ( $Param{TicketIDs}->@* ) {
        next ID if $Seen{ $ID }++;

        push @TicketIDs, $ID;
    }

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
    for my $Source ( 0 .. $#TicketIDs ) {

        for my $Target ( $Source + 1 .. $#TicketIDs ) {

            my $Success = $LinkObject->LinkAdd(
                SourceObject => 'Ticket',
                SourceKey    => $TicketIDs[$Source],
                TargetObject => 'Ticket',
                TargetKey    => $TicketIDs[$Target],
                Type         => 'Interdivisional',
                State        => 'Valid',
                UserID       => $Param{UserID},
            );
        }
    }

    return;
}

1;
